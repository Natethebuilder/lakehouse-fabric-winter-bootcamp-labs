// One participant's dedicated Fabric capacity, deployed by deploy-lab.ps1 into the
// participant's resource group. The Fabric workspace is not an ARM resource; the
// script creates it through the Fabric REST API and assigns it to this capacity.

@description('Azure region. Defaults to the resource group location so it follows the region-fallback helper.')
param location string = resourceGroup().location

@description('Capacity name: 3-63 characters, lowercase letters and digits, starting with a letter. Stable per lab.')
@minLength(3)
@maxLength(63)
param capacityName string

@description('Fabric capacity SKU. The labs are sized for one participant on an F2.')
@allowed([
  'F2'
  'F4'
  'F8'
  'F16'
  'F32'
  'F64'
])
param skuName string = 'F2'

@description('Capacity administrators: a UPN for a user or an object ID for a service principal. Participants are not capacity administrators.')
@minLength(1)
param capacityAdministrators string[]

resource capacity 'Microsoft.Fabric/capacities@2023-11-01' = {
  name: capacityName
  location: location
  sku: {
    name: skuName
    tier: 'Fabric'
  }
  properties: {
    administration: {
      members: capacityAdministrators
    }
  }
}

output capacityName string = capacity.name
output capacityResourceId string = capacity.id
output location string = capacity.location
output skuName string = capacity.sku.name
