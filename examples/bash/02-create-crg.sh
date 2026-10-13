#!/usr/bin/env bash
# Step 2 + 3: Create the Capacity Reservation Group (CRG) and a reservation with QUANTITY 0.
# Quantity 0 is pure metadata and always succeeds (behavior #2 in the article).
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

ZONES_ARGS=(); ZONE_ARGS=()
[[ -n "$ZONE" ]] && { ZONES_ARGS=(--zones "$ZONE"); ZONE_ARGS=(--zone "$ZONE"); }

# Step 2 — the "bucket": name + region + zones
az capacity reservation group create \
  -g "$RG" -n "$CRG_NAME" \
  -l "$LOCATION" \
  ${ZONES_ARGS[@]+"${ZONES_ARGS[@]}"} \
  -o table

# Step 3 — the reservation inside the CRG, starting at capacity 0
az capacity reservation create \
  -g "$RG" -c "$CRG_NAME" -n "$RES_NAME" \
  --sku "$VM_SIZE" \
  ${ZONE_ARGS[@]+"${ZONE_ARGS[@]}"} \
  --capacity 0 \
  -o table

echo "CRG $CRG_NAME and reservation $RES_NAME (capacity 0) created."
