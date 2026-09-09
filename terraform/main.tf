locals {
  platform = jsondecode(file(var.platform_json))

  bgp_router_pool_names = [
    for name, p in try(local.platform.node_pools, {}) : name
    if tostring(try(p.labels["bgp_router"], "")) == "true"
  ]
}

module "azure" {
  source = "../modules/azure"

  cluster_name                = local.platform.cluster_name
  resource_group_name         = local.platform.resource_group_name
  location                    = local.platform.location
  vnet_name                   = local.platform.network.vnet_name
  subnet_prefix               = local.platform.network.reserved.netapp_subnet_prefix
  route_server_subnet_prefix  = try(local.platform.network.reserved.route_server_subnet_prefix, "")
  bgp_router_pool_names       = local.bgp_router_pool_names
  oidc_issuer_url             = local.platform.oidc_issuer_url
  network_interface_client_id = try(local.platform.cluster_api_azure_client_id, "")
  pool_size_tib               = var.pool_size_tib
  custom_throughput_mibps     = var.custom_throughput_mibps
  tags                        = var.tags
}
