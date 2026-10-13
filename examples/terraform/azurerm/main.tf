# =============================================================================
# VM2ODCR — Terraform (azurerm) : VM + CRG + reservation, with association.
#
# ⚠️  IMPORTANT (HashiCorp azurerm behavior):
#     Setting `capacity_reservation_group_id` on `azurerm_linux_virtual_machine`
#     causes Terraform to perform an immediate STOP/DEALLOCATE of the VM, apply the
#     change, then START it again. This happens whether the VM is zonal or regional.
#     It is a function of how the azurerm provider manages the VM resource, NOT a
#     property of Azure/ARM itself. For a zero-downtime association of a running
#     ZONAL VM, use the `azapi` example in ../azapi instead.
#
# Ordering: the VM depends_on the reservation. Terraform therefore CREATES the reservation
# first and DESTROYS the VM first. Without that edge both are deleted in parallel and Azure
# returns 409 because the VM still references the reservation.
# =============================================================================

locals {
  crg_name = "crg-${var.vm_name}"
  res_name = "res-${replace(var.vm_size, "Standard_", "")}-z${var.zone}"
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# --- Networking (minimal) ----------------------------------------------------
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-vm2odcr"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.42.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.42.1.0/24"]
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-${var.vm_name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# --- Capacity Reservation Group (the bucket) --------------------------------
resource "azurerm_capacity_reservation_group" "crg" {
  name                = local.crg_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  zones               = [var.zone]
}

# --- Capacity Reservation (the actual parking spaces) -----------------------
# Applied at `reserved_count` (default 0). Raise it with a second apply once the VM is
# associated, then verify currentCapacity and virtualMachinesAllocated before calling the
# VM protected (see the top-level README).
resource "azurerm_capacity_reservation" "res" {
  name                          = local.res_name
  capacity_reservation_group_id = azurerm_capacity_reservation_group.crg.id
  zone                          = var.zone

  sku {
    name     = var.vm_size
    capacity = var.reserved_count
  }
}

# --- The VM, associated with the CRG ----------------------------------------
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = var.vm_name
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  zone                  = var.zone
  network_interface_ids = [azurerm_network_interface.nic.id]

  # ⚠️ This association triggers a deallocate -> update -> start cycle on apply.
  capacity_reservation_group_id = azurerm_capacity_reservation_group.crg.id

  # Create the reservation before the VM; destroy the VM before the reservation (avoids 409).
  depends_on = [azurerm_capacity_reservation.res]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}
