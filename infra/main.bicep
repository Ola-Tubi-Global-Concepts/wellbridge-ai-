targetScope = 'resourceGroup'

@description('Short globally unique suffix for resource names.')
param nameSuffix string

@description('Azure region for resources.')
param location string = resourceGroup().location

@description('App Service plan SKU. Review pricing before deployment.')
@allowed([
  'B1'
  'B2'
  'P0v3'
])
param appServiceSku string = 'B1'

var appName = 'wb-${nameSuffix}'
var planName = 'wb-plan-${nameSuffix}'
var insightsName = 'wb-ai-${nameSuffix}'

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  sku: {
    name: appServiceSku
    tier: contains(appServiceSku, 'P') ? 'PremiumV3' : 'Basic'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource app 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      alwaysOn: appServiceSku != 'B1'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
        { name: 'LIVE_REFERRALS_ENABLED', value: 'false' }
        { name: 'AI_FEATURES_ENABLED', value: 'false' }
      ]
    }
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: insightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    DisableIpMasking: false
  }
}

output appName string = app.name
output appUrl string = 'https://${app.properties.defaultHostName}'
output appInsightsName string = insights.name
