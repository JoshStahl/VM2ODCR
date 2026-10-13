# =============================================================================
# VM2ODCR — ADOPT an existing running VM (Terraform, azapi). The VM is NOT created,
# imported, or otherwise managed here, so its current configuration is preserved.
#
# What this does:
#   1. READS the existing VM (data source) for its size, location and zone.
#   2. Creates a CRG + a reservation that match the VM (capacity 0 by default).
#   3. PATCHes only properties.capacityReservation on the VM.
#
# Zonal VM: association without deallocation is a Microsoft Learn PREVIEW feature.
# Regional VM: must be deallocated/started around the PATCH (not automated here).
# On `terraform destroy` the VM is detached (id = null, no stop) before the CRG is removed;
# the VM itself is never deleted.
# =============================================================================

data "azapi_resource" "vm" {
  type        = "Microsoft.Compute/virtualMachines@2024-07-01"
  resource_id = var.vm_id

  response_export_values = {
    location = "location"
    size     = "properties.hardwareProfile.vmSize"
    zone     = "zones[0]"
  }
}

locals {
  vm_location = data.azapi_resource.vm.output.location
  vm_size     = data.azapi_resource.vm.output.size
  # Parent of the VM = its resource group; the CRG is created beside it.
  rg_id = regex("^(/subscriptions/[^/]+/resourceGroups/[^/]+)/", var.vm_id)[0]
}

check "zone_matches_vm" {
  assert {
    condition     = try(data.azapi_resource.vm.output.zone, "") == var.zone
    error_message = "var.zone (${var.zone}) does not match the VM's zone (${try(data.azapi_resource.vm.output.zone, "regional")}). A reservation only protects a VM with the same region, zone and size."
  }
}

resource "azapi_resource" "crg" {
  type      = "Microsoft.Compute/capacityReservationGroups@2024-07-01"
  name      = var.crg_name
  parent_id = local.rg_id
  location  = local.vm_location
  body = {
    zones = var.zone == "" ? null : [var.zone]
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

# Detach on destroy so the CRG/reservation can be deleted. azapi_update_resource is a no-op on
# destroy, so this action runs a PATCH with id = null (no stop) when the association is destroyed.
resource "azapi_resource_action" "detach_on_destroy" {
  type        = "Microsoft.Compute/virtualMachines@2024-07-01"
  resource_id = var.vm_id
  method      = "PATCH"
  when        = "destroy"
  body = {
    properties = {
      capacityReservation = {
        capacityReservationGroup = {
          id = null
        }
      }
    }
  }
  # Destroyed first of the two (it depends on the association), so detach happens before the
  # reservation and CRG are deleted.
  depends_on = [azapi_update_resource.associate]
}

output "crg_id" {
  value = azapi_resource.crg.id
}
