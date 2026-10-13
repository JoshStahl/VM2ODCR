variable "vm_id" {
  type        = string
  description = "Resource ID of the EXISTING VM to protect. Terraform does not manage the VM itself."
}

variable "crg_name" {
  type    = string
  default = "crg-adopted"
}

# Must match the VM's region and zone. Use "" for a regional VM (see README: needs reallocation).
variable "zone" {
  type    = string
  default = "1"
}

# Reservation name must be unique within the CRG; derive it from the size if you add more.
variable "reservation_name" {
  type    = string
  default = "res-adopted"
}

# 0 = metadata only. Raise to the number of VMs associated, apply again, then verify
# currentCapacity and virtualMachinesAllocated before calling the VM protected.
variable "reserved_count" {
  type    = number
  default = 0
}
