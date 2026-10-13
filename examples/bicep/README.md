# Bicep

Two templates, for two different jobs.

| File | Use it to | VM |
|---|---|---|
| [`main.bicep`](main.bicep) | Build a **new** VM that is born associated with a new CRG | Created |
| [`adopt-existing.bicep`](adopt-existing.bicep) | Protect a VM that **already exists** | Not recreated; only the association is deployed |

Names (CRG, reservation, vnet, NIC) are derived from the VM name, so these do not collide with other
labs or with a CRG you created with the CLI.

## Fresh build

```bash
az group create -n rg-vm2odcr-lab-bicep -l eastus2

# 1) reservedCount defaults to 0: metadata only, VM born associated (overallocated, not yet protected)
az deployment group create -g rg-vm2odcr-lab-bicep -f main.bicep \
  -p sshPublicKey="$(cat ~/.ssh/id_rsa.pub)"

# 2) raise capacity, then VERIFY (see top-level README) before calling the VM protected
az deployment group create -g rg-vm2odcr-lab-bicep -f main.bicep \
  -p sshPublicKey="$(cat ~/.ssh/id_rsa.pub)" reservedCount=1
```

## Adopt an existing VM

```bash
# Always preview first. Expect exactly: Create CRG, Create reservation, Modify VM.
az deployment group what-if -g <rg> -f adopt-existing.bicep -p vmName=<vm> zone=<zone> vmSize=<size>

az deployment group create  -g <rg> -f adopt-existing.bicep -p vmName=<vm> zone=<zone> vmSize=<size>
```

`zone` and `vmSize` must match the VM. Then raise `reservedCount=1` and verify.

### What was tested

Running zonal `Standard_D2s_v5` with a system-assigned identity, boot diagnostics and three tags:

| Check | Result |
|---|---|
| `what-if` | Create CRG, Create reservation, Modify VM (single property: `capacityReservation`) |
| Deploy | Succeeded |
| After | VM still running; identity, boot diagnostics, tags, disk, osProfile all preserved |

This is **observed behavior, not a documented ARM guarantee**: a VM resource deployment is a PUT, and
the template deliberately omits the rest of the VM's configuration. Run `what-if` and try a
non-production VM first. If you need a guarantee, use the REST `PATCH` in
[`../bash/03-associate-vm.sh`](../bash/03-associate-vm.sh) or the azapi Terraform example.

### Gotchas we hit

- `dependsOn: [reservation]` on the VM is **required**. The VM only references `crg.id`, so Bicep
  deploys it in parallel with the reservation and Azure rejects it:
  *"Capacity Reservation Group ... has no matching Capacity Reservations"*.
- Zonal VM association without deallocation is a Microsoft Learn **Preview** feature. A regional
  (zoneless) VM must be deallocated before and started after the deployment.
- Cleanup: delete the VM (or detach it) **before** the reservation, then the CRG. Deleting the resource
  group handles the ordering for you.
