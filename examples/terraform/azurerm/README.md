# Terraform — `azurerm`, FRESH BUILD

Builds a **new** VM, CRG and reservation, with the VM born associated. This does **not** adopt an
existing VM; for that see [`../adopt-azurerm`](../adopt-azurerm) or (recommended)
[`../adopt-azapi`](../adopt-azapi).

> **Disruption.** Setting `capacity_reservation_group_id` on an existing `azurerm_linux_virtual_machine`
> makes the `azurerm` provider stop/deallocate the VM, apply, and start it again (HashiCorp provider
> behavior, not an ARM requirement). In our adoption test that update took 1m17s vs 12s for an azapi PATCH.

## Usage

```bash
export ARM_RESOURCE_PROVIDER_REGISTRATIONS=none     # see top-level README prerequisite
terraform init

# reserved_count defaults to 0 (metadata only): the VM is associated but NOT yet protected
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"

# then raise capacity and VERIFY (top-level README) before calling the VM protected
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" -var="reserved_count=1"
```

## What was tested

Fresh build with `reserved_count = 0`, eastus2 zone 1, `Standard_D2s_v5`:

| Check | Result |
|---|---|
| `apply` | 7 resources; reservation created before the VM |
| `plan` after apply | clean (exit 0) |
| `destroy` | **single pass**, 7 destroyed, no 409 |

The VM has `depends_on = [azurerm_capacity_reservation.res]`. Without that edge Terraform deletes the VM
and the reservation in parallel and Azure returns 409 because the VM still references the reservation.
`reserved_count = 1` was not tested here (see the top-level README).
