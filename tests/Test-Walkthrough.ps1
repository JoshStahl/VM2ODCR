# Behavioral checks for cleanup ownership, error propagation and allocation verification.
$ErrorActionPreference = 'Stop'
$walkthrough = Join-Path $PSScriptRoot '../examples/powershell/odcr-walkthrough.ps1'
$credential = [pscredential]::new('testuser', (ConvertTo-SecureString 'OfflineTestOnly123!' -AsPlainText -Force))
function Get-AzResourceGroup { param($ErrorAction) if ($global:walkthroughTestCounters.existing) { [pscustomobject]@{ ResourceGroupName = 'test-rg' } } }
function New-AzResourceGroup { param($Name, $Location, [switch]$Force) $global:walkthroughTestCounters.created++ }
function New-AzVM { param($ResourceGroupName,$Name,$Location,$Size,$Image,$Credential,$PublicIpAddressName,$Zone) }
function New-AzCapacityReservationGroup { param($ResourceGroupName,$Name,$Location,$Zone) }
function New-AzCapacityReservation { param($ResourceGroupName,$ReservationGroupName,$Name,$Location,$Sku,$CapacityToReserve,$Zone) }
function Get-AzCapacityReservationGroup { param($ResourceGroupName,$Name) [pscustomobject]@{Id='/crg'} }
function Get-AzVM { param($ResourceGroupName,$Name) [pscustomobject]@{Id='/vm/target'} }
function Update-AzVM { param($ResourceGroupName,$VM,$CapacityReservationGroupId) }
function Update-AzCapacityReservation { param($ResourceGroupName,$ReservationGroupName,$Name,$CapacityToReserve) if ($global:walkthroughTestCounters.allocationFails) { throw 'SkuNotAvailable test failure' } }
function Get-AzCapacityReservation {
    param($ResourceGroupName,$ReservationGroupName,$Name,[switch]$InstanceView)
    [pscustomobject]@{Sku=[pscustomobject]@{Name='Standard_D2s_v5';Capacity=1};Zones=@('2');InstanceView=[pscustomobject]@{UtilizationInfo=[pscustomobject]@{CurrentCapacity=$global:walkthroughTestCounters.current;VirtualMachinesAllocated=@([pscustomobject]@{Id=$global:walkthroughTestCounters.allocatedId})}}}
}
function Remove-AzResourceGroup { param($Name,[switch]$Force,$ErrorAction) $global:walkthroughTestCounters.removed++; if ($global:walkthroughTestCounters.cleanupFails) { throw 'Cleanup test failure' } }
foreach ($case in @('success','existing','allocationFailure','cleanupFailure','wrongVm','currentZero')) {
    $global:walkthroughTestCounters=@{created=0;removed=0}; $script:existing=$case -eq 'existing'
    $script:allocationFails=$case -in @('allocationFailure','cleanupFailure')
    $script:cleanupFails=$case -eq 'cleanupFailure'
    $script:current=1; if ($case -eq 'currentZero') { $script:current=0 }
    $script:allocatedId='/VM/TARGET'; if ($case -eq 'wrongVm') { $script:allocatedId='/vm/other' }
    $global:walkthroughTestCounters.existing=$script:existing
    $global:walkthroughTestCounters.allocationFails=$script:allocationFails
    $global:walkthroughTestCounters.cleanupFails=$script:cleanupFails
    $global:walkthroughTestCounters.current=$script:current
    $global:walkthroughTestCounters.allocatedId=$script:allocatedId
    $caught=$null
    try { $output = (& $walkthrough -Rg test-rg -Credential $credential -Cleanup 6>&1 | Out-String) }
    catch { $caught=$_.Exception.Message }
    if ($case -eq 'existing') {
        if (-not $caught -or $global:walkthroughTestCounters.created -ne 0 -or $global:walkthroughTestCounters.removed -ne 0) { throw 'Existing group was not protected' }
    } elseif ($script:allocationFails) {
        if ($caught -notlike '*SkuNotAvailable*' -or $global:walkthroughTestCounters.removed -ne 1) { throw "Original failure or cleanup lost: $case" }
    } else {
        if ($caught -or $global:walkthroughTestCounters.removed -ne 1) { throw "Unexpected failure: $case $caught" }
        $protected=$output -match 'RESULT: protected\.'
        if ($protected -ne ($case -eq 'success')) { throw "Incorrect allocation result: $case" }
    }
    "PASS: $case"
}
