# Step 1 of the adoption flow (see README). Terraform >= 1.5 (import blocks) and
# `terraform plan -generate-config-out=generated.tf` are used to pull the VM's CURRENT
# configuration into code. The resource address below must match the generated resource.
import {
  to = azurerm_linux_virtual_machine.existing
  id = var.vm_id
}
