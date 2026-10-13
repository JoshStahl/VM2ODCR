# Terraform (`azapi`) — adopt an EXISTING running VM (recommended)

The VM is **read, not managed**: Terraform never imports it, so its current configuration is
untouched. Only `properties.capacityReservation` is PATCHed. Nothing needs to be trimmed or imported.

> Zonal association without deallocation is a Microsoft Learn **Preview** feature. Regional VMs
> must be reallocated; this example does not automate that.

## Usage

```bash
export ARM_RESOURCE_PROVIDER_REGISTRATIONS=none      # see top-level README prerequisite
terraform init
terraform apply -var="vm_id=/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<vm>"
```

Defaults: `zone = "1"`, `reserved_count = 0`. `zone` must match the VM (a `check` block warns if not).
Then raise capacity and verify:

```bash
terraform apply -var="vm_id=..." -var="reserved_count=1"
# verify currentCapacity and virtualMachinesAllocated (top-level README) before calling it protected
```

## What was tested (running zonal `Standard_D2s_v5`, tags `owner=legacy`, eastus2)

| Check | Result |
|---|---|
| `apply` (capacity 0) | 4 added; VM stayed running |
| VM config after apply | tags, size, zone unchanged; association set |
| `plan` after apply | clean (exit 0) thanks to `ignore_casing = true` |
| `destroy` | single pass, ~27s, no 409 |
| VM after destroy | still running, tags intact, **no longer associated** |

Destroy order is: detach VM (`azapi_resource_action`, `when = "destroy"`) → reservation → CRG. The CRG
carries a `retry` because Azure can briefly still list the deleted reservation as a nested resource.

Not tested here: `reserved_count = 1` (see the top-level README for the capacity result in our lab).
