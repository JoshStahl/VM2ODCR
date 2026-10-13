variable "location" {
  type    = string
  default = "eastus2"
}

variable "zone" {
  type    = string
  default = "1"
}

variable "resource_group_name" {
  type    = string
  default = "rg-vm2odcr-lab-tf"
}

variable "vm_name" {
  type    = string
  default = "vm-odcr-demo"
}

variable "vm_size" {
  type    = string
  default = "Standard_D2s_v5" # NOTE: burstable B-series is NOT eligible for ODCR
}

variable "admin_username" {
  type    = string
  default = "azureuser"
}

# Provide your own SSH public key.
variable "ssh_public_key" {
  type        = string
  description = "SSH public key for the VM admin user."
}

# Reserved instances ("parking spaces"). Default 0 = metadata-only, matching the recommended
# sequence: apply at 0, confirm association, then apply again with -var=reserved_count=1.
variable "reserved_count" {
  type    = number
  default = 0
}
