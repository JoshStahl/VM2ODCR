#!/usr/bin/env bash
# Cleanup: remove everything created by the walkthrough, in an order Azure accepts.
#
# Azure refuses to delete a reservation (409) while a VM is still associated with it, and
# VM deletion can take a moment to drop out of virtualMachinesAssociated. So:
#   1. delete the VM (this removes the association), wait for it
#   2. wait until the CRG shows no associated VMs
#   3. delete reservation, then CRG
#   4. delete the resource group
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

az vm delete -g "$RG" -n "$VM_NAME" --yes

for i in $(seq 1 30); do
  N="$(az capacity reservation group show -g "$RG" -n "$CRG_NAME" --query "length(virtualMachinesAssociated || \`[]\`)" -o tsv 2>/dev/null || echo 0)"
  [[ "$N" == "0" ]] && break
  echo "Waiting for VM association to clear ($N left)..."; sleep 10
done

az capacity reservation delete -g "$RG" -c "$CRG_NAME" -n "$RES_NAME" --yes
az capacity reservation group delete -g "$RG" -n "$CRG_NAME" --yes
az group delete -n "$RG" --yes --no-wait
echo "Delete queued for resource group $RG."
