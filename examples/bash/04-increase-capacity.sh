#!/usr/bin/env bash
# Step 4b: Increase the reservation quantity to cover the running VM (behavior #3).
#
# Because the VM is already running, it already owns a hypervisor slot, so Azure can
# link the reservation to that existing slot. Per Microsoft Learn, this step needs no
# additional quota or capacity once the VM is associated and allocated.
#
# If it fails with `SkuNotAvailable` ("Capacity Restrictions"), do NOT conclude the
# subscription type is blocked. First run ./05-verify.sh and confirm the reservation's
# region, zone and size match the VM and that the VM is in virtualMachinesAllocated.
# In our lab this step failed (D2s_v5, eastus2, zone 1) even though those matched; in a
# reviewer's sponsored POC subscription the same step succeeded. Cause was not isolated.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

TARGET="${TARGET_CAPACITY:-1}"

az capacity reservation update \
  -g "$RG" -c "$CRG_NAME" -n "$RES_NAME" \
  --capacity "$TARGET" \
  -o table

echo "Reservation $RES_NAME capacity set to $TARGET. Run ./05-verify.sh to confirm protection."
