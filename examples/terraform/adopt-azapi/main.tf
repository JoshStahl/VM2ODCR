# =============================================================================
# VM2ODCR: ADOPT an existing running VM (Terraform, azapi). The VM is NOT created,
# imported, or otherwise managed here, so its current configuration is preserved.
#
# What this does:
#   1. READS the existing VM (data source) for its size, location and zone.
#   2. Creates a CRG + a reservation that match the VM (capacity 0 by default).
#   3. PATCHes only properties.capacityReservation on the VM.
#
# Zonal VM: association without deallocation is a Microsoft Learn PREVIEW feature.
# Regional VM: must be deallocated/started around the PATCH (not automated here).
# Terraform never automatically detaches the VM during destroy. It cannot prove that the current
# association is still the CRG this configuration created, so clearing it could erase another team's change.
# =============================================================================

data "azapi_resource" "vm" {
  type        = "Microsoft.Compute/virtualMachines@2024-07-01"
  resource_id = var.vm_id

  response_export_values = {
    location = "location"
    size     = "properties.hardwareProfile.vmSize"
    zone     = "zones[0]"
    crg_id   = "properties.capacityReservation.capacityReservationGroup.id"
  }
}

locals {
  vm_location = data.azapi_resource.vm.output.location
  vm_size     = data.azapi_resource.vm.output.size
  vm_zone     = try(data.azapi_resource.vm.output.zone == null ? "" : data.azapi_resource.vm.output.zone, "")
  # Parent of the VM = its resource group; the CRG is created beside it.
  rg_id = regex("^(/subscriptions/[^/]+/resourceGroups/[^/]+)/", var.vm_id)[0]
}

resource "azapi_resource" "crg" {
  type      = "Microsoft.Compute/capacityReservationGroups@2024-07-01"
  name      = var.crg_name
  parent_id = local.rg_id
  location  = local.vm_location
  body = {
    zones = var.zone == "" ? null : [var.zone]
  }

  lifecycle {
    precondition {
      condition     = local.vm_zone == var.zone
      error_message = "var.zone (${var.zone}) does not match the VM's zone (${local.vm_zone}). A reservation only protects a VM with the same region, zone and size."
    }
    precondition {
      condition     = try(lower(data.azapi_resource.vm.output.crg_id), "") == "" || try(lower(data.azapi_resource.vm.output.crg_id), "") == lower("${local.rg_id}/providers/Microsoft.Compute/capacityReservationGroups/${var.crg_name}")
      error_message = "The VM is already associated with a different capacity reservation group. This example will not overwrite that association."
    }
  }

  # Azure can still list a just-deleted reservation as nested for a short time (409).
  retry = {
    error_message_regex  = ["CannotDeleteResource", "nested resources exist"]
    interval_seconds     = 10
    max_interval_seconds = 30
  }
}

resource "azapi_resource" "res" {
  type      = "Microsoft.Compute/capacityReservationGroups/capacityReservations@2024-07-01"
  name      = var.reservation_name
  parent_id = azapi_resource.crg.id
  location  = local.vm_location
  body = {
    sku = {
      name     = local.vm_size
      capacity = var.reserved_count
    }
    zones = var.zone == "" ? null : [var.zone]
  }
}

# Associate: PATCH of ONLY properties.capacityReservation. Nothing else on the VM is sent.
resource "azapi_update_resource" "associate" {
  type          = "Microsoft.Compute/virtualMachines@2024-07-01"
  resource_id   = var.vm_id
  ignore_casing = true # Azure echoes the CRG id with an upper-case resource group
  body = {
    properties = {
      capacityReservation = {
        capacityReservationGroup = {
          id = azapi_resource.crg.id
        }
      }
    }
  }
  depends_on = [azapi_resource.res]
}

output "crg_id" {
  value = azapi_resource.crg.id
}
