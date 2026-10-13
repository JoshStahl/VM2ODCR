#!/usr/bin/env bash
# Step 1: Create a small VM. Default is ZONAL (ZONE=1). Set ZONE="" for a regional VM.
# An existing running zonal VM can be associated with a CRG without deallocation (Preview).
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

az group create -n "$RG" -l "$LOCATION" -o table

ZONE_ARGS=()
[[ -n "$ZONE" ]] && ZONE_ARGS=(--zone "$ZONE")

az vm create \
  -g "$RG" -n "$VM_NAME" \
  --image Ubuntu2204 \
  --size "$VM_SIZE" \
  ${ZONE_ARGS[@]+"${ZONE_ARGS[@]}"} \
  --admin-username "$ADMIN_USER" \
  --generate-ssh-keys \
  --public-ip-address "" \
  --nsg-rule NONE \
  -o table

echo "VM $VM_NAME created in $LOCATION (zone: ${ZONE:-regional})."
