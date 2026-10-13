# Terraform (`azapi`): adopt an EXISTING running VM (recommended)

The VM is **read, not managed**: Terraform never imports it, so its current configuration is
untouched. Only `properties.capacityReservation` is PATCHed. Nothing needs to be trimmed or imported.

> Zonal association without deallocation is a Microsoft Learn **Preview** feature. Regional VMs
> must be reallocated; this example does not automate that.

## Usage

If you used the previous version, remove its destroy action from state **before** applying this version:

```bash
terraform state rm azapi_resource_action.detach_on_destroy
```

Run this only when that address exists in `terraform state list`. Removing it from state makes no Azure change.
Otherwise Terraform can execute the old detach action when it removes the resource from the configuration.

```bash
export ARM_RESOURCE_PROVIDER_REGISTRATIONS=none      # see top-level README prerequisite
terraform init
terraform apply -var="vm_id=/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<vm>"
```

Defaults: `zone = "1"`, `reserved_count = 0`. `zone` must match the VM; a failed match stops the plan.
Then raise capacity and verify:

```bash
terraform apply -var="vm_id=..." -var="reserved_count=1"
# verify currentCapacity and virtualMachinesAllocated (top-level README) before calling it protected
```

## What was tested (running zonal `Standard_D2s_v5`, tags `owner=legacy`, eastus2)

| Check | Result |
|---|---|
| `apply` (capacity 0) | 3 added; VM stayed running |
| VM config after apply | tags, size, zone unchanged; association set |
| `plan` after apply | clean (exit 0) thanks to `ignore_casing = true` |
| `destroy` | not automated for an adopted VM, see teardown below |

The example refuses to overwrite a VM that is already associated with another CRG. Terraform also does not
detach the VM during destroy because it cannot safely prove that the current association is still the CRG it
created.

## Teardown

Use the [Azure association removal guidance](https://learn.microsoft.com/azure/virtual-machines/capacity-reservation-remove-vm).
For a dedicated reservation, reduce its quantity to zero, verify the VM still references the expected CRG,
and detach explicitly. Reducing quantity removes capacity protection, so coordinate this step with the owner.

```bash
az capacity reservation update -g <rg> -c <crg> -n <reservation> --capacity 0
az vm show -g <rg> -n <vm> --query capacityReservation.capacityReservationGroup.id -o tsv
# Confirm the returned ID is the CRG you intend to remove before continuing.
az vm update -g <rg> -n <vm> --capacity-reservation-group None
az vm show -g <rg> -n <vm> --query capacityReservation.capacityReservationGroup.id -o tsv
# The association must be empty. Destroy removes the reservation and CRG, keeping the VM.
terraform destroy -var="vm_id=..." -var="zone=..." -var="crg_name=..." -var="reservation_name=..."
```

This deliberate manual step avoids deleting an association that an operator changed after the initial apply.

In the review lab, apply at zero, a clean plan, increase to one, target VM allocation verification,
and explicit detach followed by destroy succeeded in West US 2, zone 2, with `Standard_D2s_v5`.
The VM remained running after reservation teardown. Application interruption was not measured.
