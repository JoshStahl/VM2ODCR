# VM2ODCR: Adding an existing Azure VM to an On-Demand Capacity Reservation (ODCR)

Working, tested code for protecting a VM with an On-Demand Capacity Reservation, in **Azure CLI
(bash)**, **PowerShell (Az)**, **Terraform** (`azurerm` and `azapi`) and **Bicep**, following the
low-risk pattern from
[Demystifying On-Demand Capacity Reservations](https://techcommunity.microsoft.com/blog/azureinfrastructureblog/demystifying-on-demand-capacity-reservations/4504806).

> **Status of this repo.** Examples were run against a real subscription unless the table in
> [What was tested](#what-was-tested) says otherwise. One step could not be completed in the original lab:
> raising a reservation from 0 to 1 failed with `SkuNotAvailable`. See
> [Capacity and `SkuNotAvailable`](#capacity-and-skunotavailable).

---

## Concepts (the "parking garage")

- An **ODCR** reserves a hypervisor slot for a specific **VM size**, **region** and **zone**. A VM
  associated with it gets priority on start and a capacity SLA.
- A **Capacity Reservation Group (CRG)** is a bucket (name, region, zones). A **capacity reservation**
  inside it has a VM size, zone and **quantity**.
- **Associated vs. allocated.** *Associated* = the VM references the CRG. *Allocated* = the VM is
  consuming a reserved slot. A reservation with fewer slots than associated VMs is **overallocated**;
  the extra VMs are not protected.

### The three behaviors that make protecting existing VMs easy

1. You can add a **running** VM to a CRG.
2. You can create a reservation with quantity **0** (metadata only, needs no capacity).
3. If associated VMs exceed the reserved quantity, you can **increase** the quantity to cover them,
   because a running VM already owns a slot.

### Recommended order for an existing VM

> Bring the VM online first, then apply the reservation.

1. Create the CRG and a reservation with **quantity 0**.
2. **Associate** the running VM. The reservation is now overallocated (VM not yet protected).
3. **Raise** the quantity to the number of VMs.
4. **Verify** (below). Only then call the VM protected.

### Disruption when associating

| VM | Behavior |
|---|---|
| Not running | Applies immediately |
| Running, **zonal** | No deallocation needed. Microsoft Learn currently labels this **Preview** |
| Running, **regional** (no zone) | Must be reallocated: deallocate, set the property, start |

We confirmed that a REST `PATCH` on a **running zonal** VM succeeded and the VM stayed `running`.

## Verify before you say "protected"

Association alone is not protection. Check all of the following (`examples/bash/05-verify.sh` does):

- The reservation's **region, zone and size** match the VM.
- `sku.capacity` (the reserved quantity) is at least the number of associated VMs.
- `instanceView.utilizationInfo.currentCapacity` reflects that capacity.
- The VM appears in `instanceView.utilizationInfo.virtualMachinesAllocated`, not just in
  `virtualMachinesAssociated`.

```bash
az capacity reservation show -g <rg> -c <crg> -n <reservation> --instance-view \
  --query "{capacity:sku.capacity, current:instanceView.utilizationInfo.currentCapacity, allocated:instanceView.utilizationInfo.virtualMachinesAllocated[].id}"
```

In our runs `virtualMachinesAllocated` was sometimes empty immediately after association and populated
later, so allow a short delay before concluding anything.

## Capacity and `SkuNotAvailable`

Creating or raising a reservation to more than 0 asks Azure for real capacity, and this can fail with
`SkuNotAvailable` ("failed for Capacity Restrictions"). Quantity 0 never needs capacity.

**What we observed.** In our lab subscription (a `MngEnv` sponsored subscription), raising a reservation
from 0 to 1 failed for `Standard_D2s_v5` in eastus2 zone 1, even though the VM was running in that zone,
the reservation matched its size and zone, and `az vm list-skus` showed only zone 2 as restricted.
A probe across D, E and F families (v3 to v5), zones 1 and 3, and a regional reservation also returned
`SkuNotAvailable` every time. A reviewer ran the same step in their **own sponsored POC subscription
and it succeeded.**

**What that does and does not show.** It shows allocation was blocked for that one lab subscription. It
does **not** show that sponsored subscriptions in general cannot allocate reservations. Microsoft Learn's
only stated exclusion is Free Trial and Azure for Students subscriptions. We did not isolate the cause.

**What to do if you hit it.** Verify the region, zone and size match and that the VM is allocated (above)
before interpreting the error. Then try another size, zone or region, retry off-hours, and check quota.
If it persists, open a support request. The article lists the same remedies.

## ⚠️ Terraform: `azurerm` stops the VM, `azapi` does not

Per the source article:

> If you use the **AzureRM** provider, Terraform will always perform an immediate **stop/deallocate of
> the VM, apply the change, and then start the VM up again**. The **Azapi** provider works as documented.
> I believe this is a result of how HashiCorp coded the AzureRM provider to manage Azure resources.

We observed the cost of this: adopting a running VM took **1m17s** with `azurerm` versus **12s** with an
`azapi` PATCH. To avoid the stop/start for an existing zonal VM, use the `azapi` approach.

### Terraform prerequisite

Terraform plans stalled in provider registration in a reviewer's environment. Set this before
`terraform init/plan/apply`:

```bash
export ARM_RESOURCE_PROVIDER_REGISTRATIONS=none
```

This is an environment prerequisite (the identity may lack permission to register providers), not a
template defect. All Terraform tests here ran with it set.

---

## Examples

Fresh builds create a new VM already associated. **Adoption** examples protect a VM that already exists.

| Tool | Fresh build | Adopt an existing VM |
|---|---|---|
| Azure CLI (bash) | [`examples/bash`](examples/bash) (script 01 creates a test VM; 02 to 05 work on any VM) | same scripts |
| PowerShell (Az) | [`examples/powershell`](examples/powershell) | same script |
| Terraform `azurerm` | [`examples/terraform/azurerm`](examples/terraform/azurerm) | [`examples/terraform/adopt-azurerm`](examples/terraform/adopt-azurerm) (import; restarts the VM) |
| Terraform `azapi` | [`examples/terraform/azapi`](examples/terraform/azapi) | [`examples/terraform/adopt-azapi`](examples/terraform/adopt-azapi) (**recommended**; no import) |
| Bicep | [`examples/bicep/main.bicep`](examples/bicep/main.bicep) | [`examples/bicep/adopt-existing.bicep`](examples/bicep/adopt-existing.bicep) |

All fresh-build examples default to a reservation quantity of **0**, matching the recommended order.
Raise it in a second step (`reserved_count=1`, `reservedCount=1`, `TARGET_CAPACITY=1`, `-TargetCapacity 1`).

## What was tested

Real Azure subscription, eastus2, zone 1, `Standard_D2s_v5`, reservation quantity 0 unless noted.

| Example | Result |
|---|---|
| bash 01 to 03, 05, 99 | Passed. Verify correctly reports "NOT protected" at quantity 0. Cleanup finished in one pass |
| PowerShell | Review lab: creation, association, increase to one, target VM verification and synchronous group cleanup passed in West US 2, zone 2. Behavioral tests cover allocation failure, cleanup failure and existing group refusal on PowerShell 5.1 and 7. |
| Terraform `azurerm` fresh | apply, clean plan, single-pass destroy |
| Terraform `azapi` fresh | apply, clean plan (needs `ignore_casing`), single-pass destroy (needs `retry` on the CRG) |
| Terraform `adopt-azapi` | apply and clean plan kept tags/config and the VM stayed running. Teardown requires an explicit VM detach before removing reservation resources. |
| Terraform `adopt-azurerm` | import, in-place association, clean plan, and the safe-undo path. A plain `destroy` **deletes the VM** |
| Bicep fresh | deploy, idempotent redeploy, names derived from `vmName` |
| Bicep adopt | what-if, deploy; identity, boot diagnostics and tags preserved, VM stayed running |
| **Raising quantity 0 to 1** | Failed in the original lab. Succeeded in the review lab in West US 2, zone 2, for PowerShell, the AzAPI fresh build and AzAPI adoption. |

## Cleanup

Azure rejects deleting a reservation (`409`) while a VM still references it, and a just-deleted
reservation can briefly still be listed as nested under its CRG. Delete the VM (or detach it) first, then
the reservation, then the CRG. Deleting the whole resource group handles the order:

```bash
az group delete -n <rg> --yes --no-wait
```

A reservation with quantity above 0 **bills immediately** at the VM's rate, so remove it when finished.

PowerShell `-Cleanup` requires a new resource group and waits for deletion on success or failure.
It refuses an existing group to avoid deleting unrelated resources. Without `-Cleanup`, the lab remains for inspection.

AzAPI adoption requires explicit detach before destroy. See its README, including the state migration instruction
if you already applied the previous automatic detach action.

## Behavioral tests

These tests use controlled Azure responses and do not deploy resources:

```bash
pwsh -NoProfile -File tests/Test-Walkthrough.ps1
bash tests/test-verify.sh
```

The PowerShell test also runs with Windows PowerShell 5.1. Live validation verifies real Azure behavior separately.

---

## References

- [On-demand capacity reservation overview](https://learn.microsoft.com/azure/virtual-machines/capacity-reservation-overview)
- [Associate a VM to a capacity reservation group](https://learn.microsoft.com/azure/virtual-machines/capacity-reservation-associate-vm)
- [Remove a VM association](https://learn.microsoft.com/azure/virtual-machines/capacity-reservation-remove-vm)
- [Overallocate capacity reservations](https://learn.microsoft.com/azure/virtual-machines/capacity-reservation-overallocate)
- [Demystifying On-Demand Capacity Reservations (blog)](https://techcommunity.microsoft.com/blog/azureinfrastructureblog/demystifying-on-demand-capacity-reservations/4504806)
