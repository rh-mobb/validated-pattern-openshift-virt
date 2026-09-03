locals {
  platform = jsondecode(file(var.platform_json))
}

module "azure" {
  source = "../modules/azure"

  cluster_name            = local.platform.cluster_name
  resource_group_name     = local.platform.resource_group_name
  location                = local.platform.location
  vnet_name               = local.platform.network.vnet_name
  subnet_prefix           = local.platform.network.reserved.netapp_subnet_prefix
  oidc_issuer_url         = local.platform.oidc_issuer_url
  pool_size_tib           = var.pool_size_tib
  custom_throughput_mibps = var.custom_throughput_mibps
  tags                    = var.tags
}
