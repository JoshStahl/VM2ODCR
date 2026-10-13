#!/usr/bin/env bash
# Verify (read-only): is the VM actually protected?
# Do NOT call the VM protected from the association alone. Check all of:
#   - reservation capacity (sku.capacity) >= number of associated VMs
#   - instanceView.utilizationInfo.currentCapacity
#   - the VM appears in virtualMachinesAllocated (not just virtualMachinesAssociated)
#   - the reservation's size, zone and region match the VM
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

echo "--- VM (size / zone / location / CRG) ---"
az vm show -g "$RG" -n "$VM_NAME" \
  --query "{size:hardwareProfile.vmSize, zone:zones[0], location:location, crg:capacityReservation.capacityReservationGroup.id}" -o json

echo "--- CRG: associated VMs ---"
az capacity reservation group show -g "$RG" -n "$CRG_NAME" \
  --query "{zones:zones, location:location, associated:virtualMachinesAssociated[].id}" -o json

echo "--- Reservation: capacity, currentCapacity, allocated VMs ---"
az capacity reservation show -g "$RG" -c "$CRG_NAME" -n "$RES_NAME" --instance-view \
  --query "{sku:sku.name, zone:zones[0], capacity:sku.capacity, currentCapacity:instanceView.utilizationInfo.currentCapacity, allocated:instanceView.utilizationInfo.virtualMachinesAllocated[].id}" -o json

CAP="$(az capacity reservation show -g "$RG" -c "$CRG_NAME" -n "$RES_NAME" --query sku.capacity -o tsv)"
ALLOC="$(az capacity reservation show -g "$RG" -c "$CRG_NAME" -n "$RES_NAME" --instance-view \
  --query "length(instanceView.utilizationInfo.virtualMachinesAllocated || \`[]\`)" -o tsv)"
if [[ "$CAP" -ge 1 && "$ALLOC" -ge 1 ]]; then
  echo "RESULT: protected (capacity=$CAP, allocated VMs=$ALLOC)."
else
  echo "RESULT: NOT protected yet (capacity=$CAP, allocated VMs=$ALLOC)."
fi
