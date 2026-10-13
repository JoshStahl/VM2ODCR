#!/usr/bin/env bash
# Verify (read-only): is the VM actually protected?
# Do NOT call the VM protected from the association alone. Check all of:
#   - reservation capacity (sku.capacity) covers this reservation's allocated VMs
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
ALLOCATED_COUNT="$(az capacity reservation show -g "$RG" -c "$CRG_NAME" -n "$RES_NAME" --instance-view \
  --query "length(instanceView.utilizationInfo.virtualMachinesAllocated || \`[]\`)" -o tsv)"
VM_ID="$(az vm show -g "$RG" -n "$VM_NAME" --query id -o tsv | tr '[:upper:]' '[:lower:]')"
CURRENT_CAPACITY="$(az capacity reservation show -g "$RG" -c "$CRG_NAME" -n "$RES_NAME" --instance-view \
  --query "instanceView.utilizationInfo.currentCapacity" -o tsv)"
ALLOCATED_IDS="$(az capacity reservation show -g "$RG" -c "$CRG_NAME" -n "$RES_NAME" --instance-view \
  --query "instanceView.utilizationInfo.virtualMachinesAllocated[].id" -o tsv)"
TARGET_ALLOCATED=false
while IFS= read -r allocated_id; do
  if [[ -n "$VM_ID" && "$(printf '%s' "$allocated_id" | tr '[:upper:]' '[:lower:]')" == "$VM_ID" ]]; then
    TARGET_ALLOCATED=true
    break
  fi
done <<< "$ALLOCATED_IDS"

if [[ "$CAP" =~ ^[0-9]+$ && "$CURRENT_CAPACITY" =~ ^[0-9]+$ && "$ALLOCATED_COUNT" =~ ^[0-9]+$ && "$CAP" -ge "$ALLOCATED_COUNT" && "$CURRENT_CAPACITY" -ge "$ALLOCATED_COUNT" && "$TARGET_ALLOCATED" == true ]]; then
  echo "RESULT: protected (capacity=$CAP, allocated VMs=$ALLOCATED_COUNT, target VM allocated)."
else
  echo "RESULT: NOT protected yet (capacity=$CAP, allocated VMs=$ALLOCATED_COUNT, target VM allocated=$TARGET_ALLOCATED)."
fi
