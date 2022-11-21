terraform {

  cloud {
    organization = "olibb"
    workspaces {
      name = "Resume"
    }
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.3.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }

  }
}

#Get tenant info
data "azurerm_client_config" "current" {}

# Create resource group
resource "azurerm_resource_group" "rg" {
  name     = "rg-prod-webapp-01"
  location = "West Europe"
}

#Create Key Vault
resource "azurerm_key_vault" "keyvault" {
  name                        = "kv-prod-01"
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
}

resource "azurerm_key_vault_access_policy" "keyvault_policy_tf" {
  key_vault_id = azurerm_key_vault.keyvault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id
  secret_permissions = [
    "Get"
  ]
}

resource "azurerm_key_vault_access_policy" "keyvault_policy_functionapp" {
  key_vault_id = azurerm_key_vault.keyvault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = "0776233c-5140-4ac2-be09-f7b2a6b38582"
  secret_permissions = [
    "Get"
  ]
}

#Create empty keyvault secret
resource "azurerm_key_vault_secret" "cosmosdb_connectionstring" {
  name         = "cosmosdb-connectionstring"
  value        = ""
  key_vault_id = azurerm_key_vault.keyvault.id

  //ignore changes to avoid drift
  lifecycle {
    ignore_changes = [value, version]
  }


}


#Create storage account
resource "azurerm_storage_account" "storage" {
  name                      = "saprodwebapp"
  resource_group_name       = azurerm_resource_group.rg.name
  location                  = azurerm_resource_group.rg.location
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  enable_https_traffic_only = false
  static_website {
    index_document = "index.html"
  }
  custom_domain {
    name = "www.olibjorn.com"
  }
}


# Create CosmosDB
resource "azurerm_cosmosdb_account" "cosmosdbaccount" {
  location            = azurerm_resource_group.rg.location
  name                = "cos-prod-nosql01"
  offer_type          = "Standard"
  resource_group_name = azurerm_resource_group.rg.name
  tags = {
    defaultExperience       = "Core (SQL)"
    hidden-cosmos-mmspecial = ""
  }
  consistency_policy {
    consistency_level = "Session"
  }
  geo_location {
    failover_priority = 0
    location          = "westeurope"
  }
}
resource "azurerm_cosmosdb_sql_database" "sqldatabase_resumedb" {
  account_name        = azurerm_cosmosdb_account.cosmosdbaccount.name
  name                = "ResumeDB"
  resource_group_name = azurerm_resource_group.rg.name
}
resource "azurerm_cosmosdb_sql_container" "sqlcontainer_resume" {
  account_name        = azurerm_cosmosdb_account.cosmosdbaccount.name
  database_name       = azurerm_cosmosdb_sql_database.sqldatabase_resumedb.name
  name                = "Resume"
  partition_key_path  = "/id"
  resource_group_name = azurerm_resource_group.rg.name
}


#Create function app
resource "azurerm_application_insights" "appinsights" {
  application_type    = "web"
  location            = "westeurope"
  name                = "webapp01-prod-function"
  resource_group_name = azurerm_resource_group.rg.name
  sampling_percentage = 0
  workspace_id        = "/subscriptions/810bbab8-1930-497c-bc89-0e6aa9dbd5d1/resourcegroups/defaultresourcegroup-weu/providers/microsoft.operationalinsights/workspaces/defaultworkspace-810bbab8-1930-497c-bc89-0e6aa9dbd5d1-weu"
}

resource "azurerm_windows_function_app" "functionapp" {
  app_settings = {
    COSMOS_CONNECTIONSTRINGSETTINGS = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.cosmosdb_connectionstring.versionless_id})"
    WEBSITE_RUN_FROM_PACKAGE        = "1"
  }
  builtin_logging_enabled    = false
  client_certificate_mode    = "Required"
  location                   = azurerm_resource_group.rg.location
  name                       = "webapp01-prod-function"
  resource_group_name        = azurerm_resource_group.rg.name
  service_plan_id            = "/subscriptions/810bbab8-1930-497c-bc89-0e6aa9dbd5d1/resourceGroups/rg-prod-webapp-01/providers/Microsoft.Web/serverfarms/ASP-rgprodwebapp01-8189"
  storage_account_access_key = azurerm_storage_account.storage.primary_access_key
  storage_account_name       = azurerm_storage_account.storage.name
  tags = {
    "hidden-link: /app-insights-conn-string"         = azurerm_application_insights.appinsights.connection_string
    "hidden-link: /app-insights-instrumentation-key" = azurerm_application_insights.appinsights.instrumentation_key
    "hidden-link: /app-insights-resource-id"         = azurerm_application_insights.appinsights.id
  }
  site_config {
    application_insights_connection_string = azurerm_application_insights.appinsights.connection_string
    application_insights_key               = azurerm_application_insights.appinsights.instrumentation_key
    ftps_state                             = "FtpsOnly"
    cors {
      allowed_origins = ["https://olibjorn.com", "https://portal.azure.com", "https://www.olibjorn.com"]
    }
  }

  identity {
    type = "SystemAssigned"
  }
}
resource "azurerm_function_app_function" "httpfunction1" {
  config_json     = "{\"bindings\":[{\"authLevel\":\"function\",\"direction\":\"in\",\"methods\":[\"get\",\"post\"],\"name\":\"Request\",\"type\":\"httpTrigger\"},{\"direction\":\"out\",\"name\":\"Response\",\"type\":\"http\"},{\"collectionName\":\"Resume\",\"connectionStringSetting\":\"COSMOS_CONNECTIONSTRINGSETTINGS\",\"databaseName\":\"ResumeDB\",\"direction\":\"in\",\"name\":\"CosmosIn\",\"sqlQuery\":\"SELECT count('id') as visitorCount from c\",\"type\":\"cosmosDB\"},{\"collectionName\":\"Resume\",\"connectionStringSetting\":\"COSMOS_CONNECTIONSTRINGSETTINGS\",\"databaseName\":\"ResumeDB\",\"direction\":\"out\",\"name\":\"cosmosOut\",\"type\":\"cosmosDB\"}]}"
  function_app_id = azurerm_windows_function_app.functionapp.id
  name            = "HttpTrigger1"
}
resource "azurerm_app_service_custom_hostname_binding" "appservice_hostnamebinding" {
  app_service_name    = azurerm_windows_function_app.functionapp.name
  hostname            = "webapp01-prod-function.azurewebsites.net"
  resource_group_name = azurerm_resource_group.rg.name
}




//Decided to use Cloudflare so I destroyed this config
/* Create CDN Profile
resource "azurerm_cdn_profile" "cdnprofile" {
  name                = "OliCDNProfile"
  resource_group_name = azurerm_resource_group.rg.name
  location            = "global"
  sku                 = "Standard_Microsoft"
}

#Create CDN Endpoint
resource "azurerm_cdn_endpoint" "cdnendpoint" {
  name                   = "olicdnendpoint"
  profile_name           = "azurerm_cdn_profile.cdnprofile.name"
  location               = "global"
  resource_group_name    = azurerm_resource_group.rg.name
  is_compression_enabled = false
  origin_host_header     = "saprodwebapp.z6.web.core.windows.net"


  origin {
    name       = "saprodwebapp-z6-web-core-windows-net"
    host_name  = "saprodwebapp.z6.web.core.windows.net"
  }

  delivery_rule {
    name  = "RedirectHTTP"
    order = "1"
    request_scheme_condition {
      operator     = "Equal"
      match_values = ["HTTP"]
    }
    url_redirect_action {
      redirect_type = "PermanentRedirect"
      protocol      = "Https"
    }
  }

}

resource "azurerm_cdn_endpoint_custom_domain" "cdncustomdomain" {
  host_name       = "www.olibjorn.com"
  name            = "www-olibjorn-com"
  cdn_endpoint_id = azurerm_cdn_endpoint.cdnendpoint.id
  cdn_managed_https {
    certificate_type = "Dedicated"
    protocol_type    = "ServerNameIndication"
  }
  timeouts {
    
  }
}

#Create DNS zone
resource "azurerm_dns_zone" "dnszone" {
  name                = "olibjorn.com"
  resource_group_name = azurerm_resource_group.rg.name
}

#Create CDN Verify CNAME record
#resource "azurerm_dns_cname_record" "cname_cdnverify" {
 # name                = "cdnverify.www"
  #zone_name           = azurerm_dns_zone.dnszone.name
  #resource_group_name = azurerm_resource_group.rg.name
  #ttl                 = "3600"
  #record              = "cdnverify.olicdnendpoint.azureedge.net"
#}

#Create CDN endpoint CNAME record
resource "azurerm_dns_cname_record" "cname_www" {
  name                = "www"
  zone_name           = azurerm_dns_zone.dnszone.name
  resource_group_name = azurerm_resource_group.rg.name
  target_resource_id  = azurerm_cdn_endpoint.cdnendpoint.id
  ttl                 = "3600"
}
*/
