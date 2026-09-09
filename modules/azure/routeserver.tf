# Azure Route Server: VNet-native BGP for CUDN. Subnet name is an Azure
# constraint. No NSG and no UDR on this subnet.
resource "terraform_data" "bgp_prereqs" {
  lifecycle {
    precondition {
      condition     = trimspace(var.route_server_subnet_prefix) != ""
      error_message = "platform.json network.reserved.route_server_subnet_prefix is required (installer default 10.0.4.0/26). Re-run make cluster.<name>.platform after updating the installer."
    }

    precondition {
      condition     = length(var.bgp_router_pool_names) > 0
      error_message = "platform.json node_pools must include at least one pool with labels.bgp_router = \"true\" (clusters/aro-virt np-virt)."
    }

    precondition {
      condition     = trimspace(var.network_interface_client_id) != ""
      error_message = "platform.json cluster_api_azure_client_id is required for BGPCloudConfiguration networkInterfaceClientID (installer CAPI identity). Re-run make cluster.<name>.platform after installer apply."
    }
  }
}

resource "azurerm_subnet" "route_server" {
  name                 = "RouteServerSubnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = var.vnet_name
  address_prefixes     = [var.route_server_subnet_prefix]

  depends_on = [terraform_data.bgp_prereqs]
}

# Azure requires a Standard public IP for Route Server SDN management.
# BGP neighbors are RFC1918 virtualRouterIps — see docs/architecture.md.
resource "azurerm_public_ip" "route_server" {
  name                = "${var.cluster_name}-routeserver"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.tags

  depends_on = [terraform_data.bgp_prereqs]
}

resource "azurerm_route_server" "this" {
  name                 = "${var.cluster_name}-routeserver"
  location             = var.location
  resource_group_name  = var.resource_group_name
  sku                  = "Standard"
  public_ip_address_id = azurerm_public_ip.route_server.id
  subnet_id            = azurerm_subnet.route_server.id
  tags                 = local.tags
}
