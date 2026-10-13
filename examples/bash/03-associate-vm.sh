#!/usr/bin/env bash
# Step 4a: Associate the EXISTING VM with the CRG (behavior #1).
#
# Zonal VM   -> targeted PATCH on the running VM, no deallocation. Microsoft Learn labels
#               "associate an existing zonal VM without deallocation" as PREVIEW.
# Regional VM -> must be reallocated: deallocate, set the property, start.
#
# Why a REST PATCH instead of `az vm update --capacity-reservation-group`?
#   On a zonal VM that CLI verb sends a full PUT that includes `zones`, and in our lab it
#   failed with:  (BadRequest) Operation 'Enabling zone movement' is not supported ...
#   A PATCH of only properties.capacityReservation avoids that.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

CRG_ID="$(az capacity reservation group show -g "$RG" -n "$CRG_NAME" --query id -o tsv)"
VM_ID="/subscriptions/${SUB_ID}/resourceGroups/${RG}/providers/Microsoft.Compute/virtualMachines/${VM_NAME}"
URL="https://management.azure.com${VM_ID}?api-version=2024-07-01"
BODY="{\"properties\":{\"capacityReservation\":{\"capacityReservationGroup\":{\"id\":\"${CRG_ID}\"}}}}"

if [[ -z "$ZONE" ]]; then
  echo "Regional VM: deallocating so the association can take effect..."
  az vm deallocate -g "$RG" -n "$VM_NAME" -o none
fi

echo "Associating $VM_NAME with $CRG_NAME via targeted PATCH..."
az rest --method patch --url "$URL" --headers "Content-Type=application/json" --body "$BODY" \
  --query "properties.capacityReservation.capacityReservationGroup.id" -o tsv

if [[ -z "$ZONE" ]]; then
  az vm start -g "$RG" -n "$VM_NAME" -o none
fi

echo "Associated. With reservation capacity 0 the CRG is OVERALLOCATED (not yet protected)."
