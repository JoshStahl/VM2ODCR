# Terraform (`azurerm`) — adopt an EXISTING running VM

Use this when the VM already exists and you want azurerm to manage it **and** associate it with a
CRG, keeping its current configuration. Prefer [`../adopt-azapi`](../adopt-azapi) when you only
need the association: it never imports the VM and does not bounce it.

> **Disruption.** Associating through `azurerm` updates the VM resource in place, but the provider
> stops/deallocates, updates and restarts it. In our test the update took **1m17s** (the equivalent
> azapi PATCH took 12s). The plan shows `1 to change`, not a replacement, so the VM is not deleted.

## Flow (tested against a running zonal `Standard_D2s_v5`, azurerm 4.x, Terraform 1.15)

```bash
export ARM_RESOURCE_PROVIDER_REGISTRATIONS=none     # see top-level README prerequisite
export TF_VAR_vm_id=/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<vm>

terraform init
terraform plan -generate-config-out=generated.tf     # 1. pull the VM's current config into code
```

`generate-config-out` is experimental and, for a VM, emits config that Terraform then rejects. In
our test these lines had to be **deleted from `generated.tf`**:

| Generated line | Why it fails |
|---|---|
| `os_managed_disk_id = "..."` | Conflicts with `admin_username`, `computer_name`, `source_image_reference`, `admin_ssh_key`, `patch_mode` and others (attach-existing-disk vs image-based VM) |
| `platform_fault_domain = -1` | Only valid together with `virtual_machine_scale_set_id` |

Also review the generated `admin_ssh_key` (it contains the public key inline) and any `null` values.

```bash
terraform plan        # 2. REQUIRED: must say "1 to import, 0 to add, 0 to change, 0 to destroy"
terraform apply       #    imports the VM into state; changes nothing in Azure
```

Do **not** continue if step 2 shows changes or a replacement for the VM; fix `generated.tf` until it
is clean.

```bash
cp crg.tf.example crg.tf                               # 3. add CRG + reservation (capacity 0)
export TF_VAR_resource_group_name=<rg>                 #    location/zone/size default to eastus2 / 1 / Standard_D2s_v5;
                                                       #    set TF_VAR_location / _zone / _vm_size to match YOUR VM
# edit generated.tf as described at the bottom of crg.tf.example
terraform plan        #    expect: VM "will be updated in-place", Plan: 2 to add, 1 to change, 0 to destroy
terraform apply
terraform plan        #    expect: No changes
```

`crg.tf.example` takes location, zone and size as **variables**, not from the imported VM resource.
The VM depends on the reservation, so referencing the VM from the reservation creates a
dependency cycle (`Error: Cycle`). Keep them in sync with the VM by hand.

Then raise `-var=reserved_count=1`, apply again, and verify `currentCapacity` and
`virtualMachinesAllocated` (top-level README) before calling the VM protected.

## ⚠️ `terraform destroy` will DELETE the adopted VM

Once imported, the VM is an ordinary managed resource. In our test, `terraform plan -destroy`
reported `3 to destroy`: the reservation, the CRG **and the VM**. To undo only the reservation:

```bash
# 1. set capacity_reservation_group_id = null in generated.tf, then:
terraform apply                                        # detaches; VM stays (azurerm restarts it again)
# 2. stop managing the VM (changes nothing in Azure):
terraform state rm azurerm_linux_virtual_machine.existing
# 3. now destroy only reservation + CRG:
terraform plan -destroy                                # expect: 2 to destroy
terraform destroy
```

Tested: the VM was still running, with its tags, and no longer associated. Consider adding
`lifecycle { prevent_destroy = true }` to the imported VM in `generated.tf`.

## Notes

- Import blocks need Terraform >= 1.5; `terraform plan -generate-config-out` is experimental.
- Regional (zoneless) VMs need reallocation regardless of provider.
- Tested end to end: import, clean import plan, association (in-place), clean plan afterwards, and the
  undo above, against a real running zonal VM. Capacity was left at 0 (see the README for the
  capacity-increase result in our lab).
