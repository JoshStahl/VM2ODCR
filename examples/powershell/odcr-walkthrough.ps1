<#
    VM2ODCR — PowerShell (Az module) walkthrough.

    Adds an EXISTING VM to an On-Demand Capacity Reservation using the low-risk
    order: create CRG + reservation (qty 0) -> associate running VM -> raise qty -> verify.

    Prereqs:
        Install-Module Az -Scope CurrentUser
        Connect-AzAccount
        Set-AzContext -Subscription "<your-sub-id>"

    Every variable can be overridden with parameters so you can run this beside other labs:
        ./odcr-walkthrough.ps1 -Rg rg-my-test -VmName vm-my -Cleanup
#>
param(
    [string]$Location  = 'eastus2',
    [string]$Zone      = '1',                    # use '' for a REGIONAL (zoneless) VM
    [string]$Rg        = 'rg-vm2odcr-lab-ps',
    [string]$VmName    = 'vm-odcr-ps',
    [string]$VmSize    = 'Standard_D2s_v5',      # check the supported-size list in the ODCR overview
    [string]$AdminUser = 'azureuser',
    [int]$TargetCapacity = 1,
    [pscredential]$Credential,                   # optional; prompts if omitted
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'
$CrgName = "crg-$VmName"
$ResName = "res-$($VmSize -replace '^Standard_','')-z$(if ($Zone) { $Zone } else { 'regional' })"
$zoneArgs = if ($Zone) { @{ Zone = $Zone } } else { @{} }

# ---- Step 1: Resource group + small VM -------------------------------------
New-AzResourceGroup -Name $Rg -Location $Location -Force | Out-Null

# Prompt for the local admin credential (password auth for brevity) unless supplied.
$cred = if ($Credential) { $Credential } else { Get-Credential -UserName $AdminUser -Message 'Enter a password for the VM admin user' }

New-AzVM `
    -ResourceGroupName $Rg `
    -Name $VmName `
    -Location $Location `
    -Size $VmSize `
    -Image 'Ubuntu2204' `
    -Credential $cred `
    -PublicIpAddressName $null `
    @zoneArgs | Out-Null

Write-Host "VM $VmName created in $Location (zone: $(if ($Zone) { $Zone } else { 'regional' }))."

# ---- Step 2: Capacity Reservation Group (the bucket) -----------------------
New-AzCapacityReservationGroup `
    -ResourceGroupName $Rg `
    -Name $CrgName `
    -Location $Location `
    @zoneArgs | Out-Null

# ---- Step 3: Reservation inside the CRG, starting at capacity 0 ------------
# Quantity 0 is pure metadata and always succeeds (behavior #2).
# -Sku is the VM size STRING (not an Sku object); -Location and -CapacityToReserve are mandatory.
New-AzCapacityReservation `
    -ResourceGroupName $Rg `
    -ReservationGroupName $CrgName `
    -Name $ResName `
    -Location $Location `
    -Sku $VmSize `
    -CapacityToReserve 0 `
    @zoneArgs | Out-Null

Write-Host "CRG $CrgName and reservation $ResName (capacity 0) created."

# ---- Step 4a: Associate the EXISTING VM with the CRG (behavior #1) ---------
# Zonal VM    : association on the running VM, no deallocation (Microsoft Learn labels this Preview).
# Regional VM : must be reallocated -> Stop-AzVM (deallocate), set the property, Start-AzVM.
$crg = Get-AzCapacityReservationGroup -ResourceGroupName $Rg -Name $CrgName
if (-not $Zone) { Stop-AzVM -ResourceGroupName $Rg -Name $VmName -Force | Out-Null }

$vm = Get-AzVM -ResourceGroupName $Rg -Name $VmName
Update-AzVM -ResourceGroupName $Rg -VM $vm -CapacityReservationGroupId $crg.Id | Out-Null

if (-not $Zone) { Start-AzVM -ResourceGroupName $Rg -Name $VmName | Out-Null }
Write-Host "Associated $VmName with $CrgName. With capacity 0 the CRG is overallocated (not yet protected)."

# ---- Step 4b: Raise the reservation quantity to protect the VM (behavior #3)
# If this fails with SkuNotAvailable, verify region/zone/size match and the VM is allocated
# (see the verify block below) before concluding anything about the subscription.
Update-AzCapacityReservation `
    -ResourceGroupName $Rg `
    -ReservationGroupName $CrgName `
    -Name $ResName `
    -CapacityToReserve $TargetCapacity | Out-Null

# ---- Verify: do not call the VM protected until all of this is true --------
$cr = Get-AzCapacityReservation -ResourceGroupName $Rg -ReservationGroupName $CrgName -Name $ResName -InstanceView
$allocated = @($cr.InstanceView.UtilizationInfo.VirtualMachinesAllocated)
[pscustomobject]@{
    Sku             = $cr.Sku.Name
    Zone            = ($cr.Zones -join ',')
    Capacity        = $cr.Sku.Capacity
    CurrentCapacity = $cr.InstanceView.UtilizationInfo.CurrentCapacity
    AllocatedVMs    = ($allocated.Id -join ';')
} | Format-List

if ($cr.Sku.Capacity -ge 1 -and $allocated.Count -ge 1) { Write-Host 'RESULT: protected.' }
else { Write-Host 'RESULT: NOT protected yet (capacity 0 or VM not in virtualMachinesAllocated).' }

# ---- Cleanup (pass -Cleanup) -----------------------------------------------
# Reservation delete returns 409 while a VM is still associated, so delete the VM first.
if ($Cleanup) {
    Remove-AzVM -ResourceGroupName $Rg -Name $VmName -Force | Out-Null
    $deadline = (Get-Date).AddMinutes(5)
    do {
        $g = Get-AzCapacityReservationGroup -ResourceGroupName $Rg -Name $CrgName
        if (-not $g.VirtualMachinesAssociated) { break }
        Start-Sleep -Seconds 10
    } while ((Get-Date) -lt $deadline)
    Remove-AzCapacityReservation -ResourceGroupName $Rg -ReservationGroupName $CrgName -Name $ResName -Confirm:$false | Out-Null
    Remove-AzCapacityReservationGroup -ResourceGroupName $Rg -Name $CrgName -Confirm:$false | Out-Null
    Remove-AzResourceGroup -Name $Rg -Force -AsJob | Out-Null
    Write-Host "Cleanup started for $Rg."
}
