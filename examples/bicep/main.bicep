// =============================================================================
// VM2ODCR — Bicep FRESH BUILD: VM + Capacity Reservation Group + reservation, associated.
//
// This template CREATES a new VM that is born associated with the CRG. It does NOT adopt an
// existing VM: redeploying a VM resource means restating its whole configuration, and a mismatch
// can fail or change the VM. To protect a VM that already exists, see ./adopt-existing.bicep.
//
// Recommended sequence: deploy with reservedCount = 0 (default), confirm the association, then
// redeploy with reservedCount = 1 and verify currentCapacity and virtualMachinesAllocated.
// =============================================================================

@description('Azure region.')
param location string = resourceGroup().location

@description('Availability zone for the VM and reservation.')
param zone string = '1'

@description('VM name. CRG, reservation, vnet and NIC names are derived from it so deployments do not collide.')
param vmName string = 'vm-odcr-demo'

@description('VM size. Check the supported-size list in the ODCR overview.')
param vmSize string = 'Standard_D2s_v5'

@description('Admin username.')
param adminUsername string = 'azureuser'

@description('SSH public key for the admin user.')
param sshPublicKey string

@description('Reserved instances ("parking spaces"). Default 0 = metadata only; raise to 1 after the VM is associated.')
param reservedCount int = 0

var crgName = 'crg-${vmName}'
var reservationName = 'res-${replace(vmSize, 'Standard_', '')}-z${zone}'

// --- Networking (minimal) ---------------------------------------------------
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${vmName}'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.42.0.0/16'] }
    subnets: [
      {
        name: 'default'
        properties: { addressPrefix: '10.42.1.0/24' }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${vmName}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: vnet.properties.subnets[0].id }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// --- Capacity Reservation Group (the bucket) --------------------------------
resource crg 'Microsoft.Compute/capacityReservationGroups@2024-07-01' = {
  name: crgName
  location: location
  zones: [zone]
}

// --- Capacity Reservation (the parking spaces) ------------------------------
resource reservation 'Microsoft.Compute/capacityReservationGroups/capacityReservations@2024-07-01' = {
  parent: crg
  name: reservationName
  location: location
  sku: {
    name: vmSize
    capacity: reservedCount
  }
  zones: [zone]
}

// --- VM, associated with the CRG --------------------------------------------
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  zones: [zone]
  properties: {
    hardwareProfile: { vmSize: vmSize }
    // The association: link the VM to the CRG.
    capacityReservation: {
      capacityReservationGroup: {
        id: crg.id
      }
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [
        { id: nic.id }
      ]
    }
  }
  // Ensure the reservation exists before the VM references the group.
  dependsOn: [reservation]
}
