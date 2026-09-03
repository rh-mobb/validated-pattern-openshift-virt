mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      client_id       = "00000000-0000-0000-0000-000000000002"
      object_id       = "00000000-0000-0000-0000-000000000003"
      subscription_id = "00000000-0000-0000-0000-000000000004"
    }
  }
}

variables {
  cluster_name        = "test-cluster"
  resource_group_name = "test-rg"
  location            = "uksouth"
  vnet_name           = "test-cluster-vnet"
  subnet_prefix       = "10.0.3.0/24"
  oidc_issuer_url     = "https://uksouth.oic.aro.azure.com/tenant/test"
}

run "delegates_subnet_to_netapp_without_nsg" {
  command = plan

  assert {
    condition     = azurerm_subnet.netapp.delegation[0].service_delegation[0].name == "Microsoft.Netapp/volumes"
    error_message = "ANF subnet must be delegated to Microsoft.Netapp/volumes (azurerm enum; Azure service Microsoft.NetApp/volumes)."
  }

  assert {
    condition     = azurerm_subnet.netapp.address_prefixes[0] == "10.0.3.0/24"
    error_message = "ANF subnet prefix must come from the platform reserved CIDR."
  }
}

run "pool_is_flexible_manual" {
  command = plan

  assert {
    condition     = azurerm_netapp_pool.this.service_level == "Flexible"
    error_message = "Capacity pool service_level must be Flexible."
  }

  assert {
    condition     = azurerm_netapp_pool.this.qos_type == "Manual"
    error_message = "Capacity pool qos_type must be Manual for Trident maxThroughput."
  }

  assert {
    condition     = azurerm_netapp_pool.this.size_in_tb == 1
    error_message = "Default pool size must be 1 TiB."
  }

  assert {
    condition     = azurerm_netapp_pool.this.custom_throughput_mibps == 128
    error_message = "Flexible Manual QoS requires custom_throughput_mibps (Azure minimum 128)."
  }
}

run "trident_identity_federates_controller_sa" {
  command = plan

  assert {
    condition     = azurerm_federated_identity_credential.trident[0].subject == "system:serviceaccount:trident:trident-controller"
    error_message = "Federated credential must trust trident/trident-controller."
  }

  assert {
    condition     = contains(azurerm_federated_identity_credential.trident[0].audience, "api://AzureADTokenExchange")
    error_message = "Federated credential audience must be api://AzureADTokenExchange."
  }
}

run "skips_federated_credential_without_oidc" {
  command = plan

  variables {
    oidc_issuer_url = ""
  }

  assert {
    condition     = length(azurerm_federated_identity_credential.trident) == 0
    error_message = "Empty oidc_issuer_url must skip the federated credential."
  }
}
