#!/usr/bin/env bash
# Shared variables for the Azure CLI (bash) walkthrough.
# Source this file before running the numbered scripts:  source ./00-vars.sh
# Every value can be overridden from the environment, e.g.  RG=my-rg ./01-create-vm.sh
set -euo pipefail

export LOCATION="${LOCATION:-eastus2}"
export ZONE="${ZONE:-1}"                  # set ZONE="" for a REGIONAL (zoneless) VM
export RG="${RG:-rg-vm2odcr-lab}"
export VM_NAME="${VM_NAME:-vm-odcr-demo}"
export VM_SIZE="${VM_SIZE:-Standard_D2s_v5}"   # NOTE: check the supported-size list in the ODCR overview
export ADMIN_USER="${ADMIN_USER:-azureuser}"

export CRG_NAME="${CRG_NAME:-crg-${VM_NAME}}"
export RES_NAME="${RES_NAME:-res-${VM_SIZE#Standard_}-z${ZONE:-regional}}"

# Derived at runtime
export SUB_ID="$(az account show --query id -o tsv)"
