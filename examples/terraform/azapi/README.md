# Terraform — `azapi`, FRESH BUILD

Builds a **new** VM (with azurerm), then creates the CRG and reservation and associates the VM with
azapi (`azapi_update_resource`, a PATCH of `properties.capacityReservation`). This does **not** adopt an
existing VM; for that use [`../adopt-azapi`](../adopt-azapi).

> Zonal association without deallocation is a Microsoft Learn **Preview** feature. The azapi provider
> sends the PATCH directly, so the VM is not stopped (unlike `azurerm`).

## Usage

```bash
export ARM_RESOURCE_PROVIDER_REGISTRATIONS=none     # see top-level README prerequisite
terraform init

# reserved_count defaults to 0: the VM is associated but NOT yet protected
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"

# then raise capacity and VERIFY (top-level README) before calling the VM protected
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" -var="reserved_count=1"
```

## What was tested

Fresh build with `reserved_count = 0`, eastus2 zone 1, `Standard_D2s_v5`:

| Check | Result |
|---|---|
| `apply` | 8 resources |
| `plan` after apply | **clean** with `ignore_casing = true` |
| `plan` after apply, flag removed | **drift**: another PATCH proposed solely to change `RG-...` (upper case, as Azure echoes it) to `rg-...` |
| `destroy` | **single pass**, 8 destroyed |

Two things make destroy work in one pass:

1. The VM has `depends_on = [azapi_resource.res]`, so the VM is deleted before the reservation.
2. The CRG has a `retry` on `CannotDeleteResource`. Even after the reservation delete reports success,
   Azure can briefly still list it as a nested resource. Before the retry, the first `destroy` failed
   with a 409 on the CRG and a second `destroy` succeeded.

`reserved_count = 1` was not tested here (see the top-level README).
