#!/usr/bin/env bash
# Exercise the real verification script with controlled Azure CLI responses.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
az() {
  case "$*" in
    *"account show"*) echo test-sub ;;
    *"--query id -o tsv"*) echo /vm/target ;;
    *"--query sku.capacity"*) echo 1 ;;
    *"--query length("*) echo 1 ;;
    *"--query instanceView.utilizationInfo.currentCapacity"*) echo "$CURRENT" ;;
    *"--query instanceView.utilizationInfo.virtualMachinesAllocated[].id"*)
      if [[ "$CASE" == lookupFailure ]]; then return 7; fi
      echo "$ALLOCATED" ;;
    *) echo '{}' ;;
  esac
}
export -f az
for CASE in success wrongVm currentZero lookupFailure; do
  export CASE CURRENT=1 ALLOCATED=/VM/TARGET
  [[ "$CASE" != wrongVm ]] || export ALLOCATED=/vm/other
  [[ "$CASE" != currentZero ]] || export CURRENT=0
  status=0
  output="$(bash "$ROOT/examples/bash/05-verify.sh")" || status=$?
  if [[ "$CASE" == lookupFailure ]]; then
    [[ "$status" -ne 0 ]] || { echo 'Lookup failure was hidden'; exit 1; }
  else
    [[ "$status" -eq 0 ]] || exit 1
    if [[ "$CASE" == success ]]; then
      [[ "$output" == *'RESULT: protected '* ]] || exit 1
    else
      [[ "$output" == *'RESULT: NOT protected '* ]] || exit 1
    fi
  fi
  echo "PASS: $CASE"
done
