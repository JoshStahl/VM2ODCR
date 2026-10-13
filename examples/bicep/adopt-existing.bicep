// =============================================================================
// VM2ODCR: Bicep ADOPT an EXISTING running VM.
//
// Creates a CRG + reservation that match the VM, then deploys ONLY the association onto the
// existing VM (properties.capacityReservation). Nothing else about the VM is restated.
//
// Observed behavior (tested on a running zonal D2s_v5 with a system-assigned identity, boot
// diagnostics and 3 tags): identity, boot diagnostics, tags, disk and osProfile were preserved and
// the VM stayed running. That is observed, not a documented ARM guarantee, so ALWAYS run
//   az deployment group what-if ...
// first and try it on a non-production VM.
//
// location, zone and vmSize MUST match the VM. A reservation only protects a VM with the same
// region, zone and size. Zonal association without deallocation is a Microsoft Learn PREVIEW
// feature; a regional (zoneless) VM must be deallocated before and started after this deployment.
// =============================================================================

@description('Name of the EXISTING VM in this resource group.')
param vmName string

@description('Region of the VM.')
param location string = resourceGroup().location

@description('Availability zone of the VM.')
param zone string = '1'

@description('Size of the VM (the reservation must match it).')
param vmSize string = 'Standard_D2s_v5'

@description('CRG name. Derived from the VM name so it cannot collide with other labs.')
param crgName string = 'crg-${vmName}'

@description('Reserved instances. Default 0 = metadata only; raise to 1 after the VM is associated and verify.')
param reservedCount int = 0

var reservationSuffix = empty(zone) ? 'regional' : 'z${zone}'

resource crg 'Microsoft.Compute/capacityReservationGroups@2024-07-01' = {
  name: crgName
  location: location
  zones: empty(zone) ? null : [zone]
}

resource reservation 'Microsoft.Compute/capacityReservationGroups/capacityReservations@2024-07-01' = {
  parent: crg
  name: 'res-${replace(vmSize, 'Standard_', '')}-${reservationSuffix}'
  location: location
  sku: {
    name: vmSize
    capacity: reservedCount
  }
  zones: empty(zone) ? null : [zone]
}

// Association only. `dependsOn` is REQUIRED: the VM references only crg.id, so without it Bicep
// deploys the VM in parallel with the reservation and Azure rejects it ("no matching Capacity
// Reservations").
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  zones: empty(zone) ? null : [zone]
  dependsOn: [reservation]
  properties: {
    capacityReservation: {
      capacityReservationGroup: {
        id: crg.id
      }
    }
  }
}
