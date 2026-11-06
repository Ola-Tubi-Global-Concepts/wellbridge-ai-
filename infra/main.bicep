@description('Azure region. Confirm regional availability and data-residency requirements before deployment.')
param location string = resourceGroup().location
@description('Unique app name: 3-24 lowercase alphanumeric characters.')
@minLength(3)
@maxLength(24)
param appName string
@description('App Service plan SKU. Basic supports regional VNet integration; confirm current SKU support before deployment.')
param appServicePlanSku string = 'B1'
param postgresAdminLogin string
@secure()
param postgresAdminPassword string
param postgresSkuName string = 'Standard_B1ms'
param postgresStorageSizeGB int = 32

var planName = '${appName}-plan'
var webName = '${appName}-web'
var pgName = '${appName}-pg'
var vaultName = take(replace('${appName}vault','-',''),24)
var vnetName = '${appName}-vnet'
var postgresDnsZoneName = 'private.postgres.database.azure.com'
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.42.0.0/16'] }
    subnets: [
      { name: 'app-integration', properties: { addressPrefix: '10.42.1.0/24', delegations: [{ name: 'appservice-delegation', properties: { serviceName: 'Microsoft.Web/serverFarms' } }] } }
      { name: 'postgres-delegated', properties: { addressPrefix: '10.42.2.0/24', delegations: [{ name: 'postgres-delegation', properties: { serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers' } }] } }
    ]
  }
}
resource appSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = { parent: vnet, name: 'app-integration' }
resource postgresSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = { parent: vnet, name: 'postgres-delegated' }
resource postgresDns 'Microsoft.Network/privateDnsZones@2020-06-01' = { name: postgresDnsZoneName, location: 'global' }
resource postgresDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = { parent: postgresDns, name: '${appName}-vnet-link', location: 'global', properties: { virtualNetwork: { id: vnet.id }, registrationEnabled: false } }

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  sku: { name: appServicePlanSku, tier: 'Basic', capacity: 1 }
  kind: 'linux'
  properties: { reserved: true }
}
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${appName}-appi'
  location: location
  kind: 'web'
  properties: { Application_Type: 'web', RetentionInDays: 90 }
}
resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: webName
  location: location
  kind: 'app,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    virtualNetworkSubnetId: appSubnet.id
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      appCommandLine: 'node server.js'
      alwaysOn: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      appSettings: [
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
        { name: 'NODE_ENV', value: 'production' }
        { name: 'LIVE_REFERRALS_ENABLED', value: 'false' }
        { name: 'AUTH_MODE', value: 'entra-required-before-production' }
        { name: 'AZURE_KEY_VAULT_URL', value: 'https://${vaultName}.vault.azure.net/' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
      ]
    }
  }
}
resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: vaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enablePurgeProtection: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    publicNetworkAccess: 'Enabled'
  }
}
resource vaultAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, app.identity.principalId, keyVaultSecretsUserRoleId)
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
  }
}
resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: pgName
  location: location
  sku: { name: postgresSkuName, tier: 'Burstable' }
  properties: {
    version: '16'
    administratorLogin: postgresAdminLogin
    administratorLoginPassword: postgresAdminPassword
    storage: { storageSizeGB: postgresStorageSizeGB, autoGrow: 'Enabled' }
    backup: { backupRetentionDays: 7, geoRedundantBackup: 'Disabled' }
    network: {
      delegatedSubnetResourceId: postgresSubnet.id
      privateDnsZoneArmResourceId: postgresDns.id
      publicNetworkAccess: 'Disabled'
    }
  }
  dependsOn: [postgresDnsLink]
}
resource db 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pg
  name: 'wellbridge'
  properties: { charset: 'UTF8', collation: 'en_US.utf8' }
}
output appUrl string = 'https://${app.properties.defaultHostName}'
output appName string = app.name
output postgresServerName string = pg.name
output appPrincipalId string = app.identity.principalId
output keyVaultUri string = vault.properties.vaultUri