output "subnet_id" {
  value = module.azure.subnet_id
}

output "subnet_name" {
  value = module.azure.subnet_name
}

output "netapp_account_name" {
  value = module.azure.netapp_account_name
}

output "capacity_pool_name" {
  value = module.azure.capacity_pool_name
}

output "trident_client_id" {
  value = module.azure.trident_client_id
}

output "trident_identity_id" {
  value = module.azure.trident_identity_id
}

output "cluster_name" {
  value = local.platform.cluster_name
}

output "resource_group_name" {
  value = local.platform.resource_group_name
}

output "location" {
  value = local.platform.location
}

output "subscription_id" {
  value = local.platform.subscription_id
}

output "tenant_id" {
  value = local.platform.tenant_id
}

output "vnet_name" {
  value = local.platform.network.vnet_name
}

output "route_server_name" {
  value = module.azure.route_server_name
}

output "bgp_client_id" {
  value = module.azure.bgp_client_id
}

output "network_interface_client_id" {
  description = "Installer cluster-api-azure client ID for BGPCloudConfiguration networkInterfaceClientID."
  value       = try(local.platform.cluster_api_azure_client_id, "")
}
