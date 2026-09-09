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
  cluster_name                = "test-cluster"
  resource_group_name         = "test-rg"
  location                    = "uksouth"
  vnet_name                   = "test-cluster-vnet"
  subnet_prefix               = "10.0.3.0/24"
  route_server_subnet_prefix  = "10.0.4.0/26"
  bgp_router_pool_names       = ["np-virt"]
  oidc_issuer_url             = "https://uksouth.oic.aro.azure.com/tenant/test"
  network_interface_client_id = "00000000-0000-0000-0000-000000000097"
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

  assert {
    condition     = length(azurerm_federated_identity_credential.bgp) == 0
    error_message = "Empty oidc_issuer_url must skip the BGP federated credential."
  }
}

run "route_server_subnet_is_named_routeserversubnet" {
  command = plan

  assert {
    condition     = azurerm_subnet.route_server.name == "RouteServerSubnet"
    error_message = "Azure Route Server subnet must be named RouteServerSubnet."
  }

  assert {
    condition     = azurerm_subnet.route_server.address_prefixes[0] == "10.0.4.0/26"
    error_message = "Route Server subnet prefix must come from the platform reserved CIDR."
  }

  assert {
    condition     = azurerm_public_ip.route_server.sku == "Standard"
    error_message = "Route Server public IP must be Standard SKU."
  }

  assert {
    condition     = azurerm_route_server.this.sku == "Standard"
    error_message = "Route Server sku must be Standard."
  }
}

run "bgp_identity_federates_operator_sa" {
  command = plan

  assert {
    condition     = azurerm_federated_identity_credential.bgp[0].subject == "system:serviceaccount:openshift-bgp-cloud-connector:openshift-bgp-cloud-connector-controller-manager"
    error_message = "Federated credential must trust the bgp-cloud-connector manager ServiceAccount."
  }
}

run "bgp_role_is_route_server_only" {
  command = plan

  assert {
    condition = !contains(
      azurerm_role_definition.bgp_cloud_connector.permissions[0].actions,
      "Microsoft.Network/networkInterfaces/write"
    )
    error_message = "Sibling BGP MI must not grant NIC write; ARO speaker NICs are in the managed RG. Use installer cluster-api-azure via networkInterfaceClientID."
  }

  assert {
    condition = !contains(
      azurerm_role_definition.bgp_cloud_connector.permissions[0].actions,
      "Microsoft.Network/networkInterfaces/read"
    )
    error_message = "Sibling BGP MI must not grant NIC read in the customer RG; NIC forwarding uses CAPI in the managed RG."
  }

  assert {
    condition = contains(
      azurerm_role_definition.bgp_cloud_connector.permissions[0].actions,
      "Microsoft.Network/virtualHubs/bgpConnections/write"
    )
    error_message = "Sibling BGP MI must still write Route Server BGP connections."
  }

  assert {
    condition = !contains(
      azurerm_role_definition.bgp_cloud_connector.permissions[0].actions,
      "Microsoft.Network/routeServers/read"
    )
    error_message = "Azure RBAC does not accept Microsoft.Network/routeServers/*; Route Server is virtualHubs."
  }
}

run "fails_without_bgp_speaker_pools" {
  command = plan

  variables {
    bgp_router_pool_names = []
  }

  expect_failures = [
    terraform_data.bgp_prereqs,
  ]
}

run "fails_without_capi_network_interface_client_id" {
  command = plan

  variables {
    network_interface_client_id = ""
  }

  expect_failures = [
    terraform_data.bgp_prereqs,
  ]
}
