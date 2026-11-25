output "installer" {
  value = try(local.platform.installer, "azure")
}

output "cluster_name" {
  value = local.platform.cluster_name
}

# --- Azure (module.azure[0]) ---

output "subnet_id" {
  value = try(module.azure[0].subnet_id, null)
}

output "subnet_name" {
  value = try(module.azure[0].subnet_name, null)
}

output "netapp_account_name" {
  value = try(module.azure[0].netapp_account_name, null)
}

output "capacity_pool_name" {
  value = try(module.azure[0].capacity_pool_name, null)
}

output "trident_client_id" {
  value = try(module.azure[0].trident_client_id, null)
}

output "trident_identity_id" {
  value = try(module.azure[0].trident_identity_id, null)
}

output "resource_group_name" {
  value = try(local.platform.resource_group_name, null)
}

output "location" {
  value = try(local.platform.location, null)
}

output "subscription_id" {
  value = try(local.platform.subscription_id, null)
}

output "tenant_id" {
  value = try(local.platform.tenant_id, null)
}

output "vnet_name" {
  value = try(local.platform.network.vnet_name, null)
}

output "route_server_name" {
  value = try(module.azure[0].route_server_name, null)
}

output "bgp_client_id" {
  value = try(module.azure[0].bgp_client_id, null)
}

output "network_interface_client_id" {
  description = "Installer cluster-api-azure client ID for BGPCloudConfiguration networkInterfaceClientID."
  value       = try(local.platform.cluster_api_azure_client_id, "")
}

# --- GCP (module.gcp[0]) ---

output "gcp_project_id" {
  value = try(module.gcp[0].gcp_project_id, null)
}

output "gcp_region" {
  value = try(module.gcp[0].gcp_region, null)
}

output "storage_zone" {
  value = try(module.gcp[0].storage_zone, null)
}

output "storage_pool_name" {
  value = try(module.gcp[0].storage_pool_name, null)
}

output "storage_pool_path" {
  value = try(module.gcp[0].storage_pool_path, null)
}

output "storage_class_name" {
  value = try(module.gcp[0].storage_class_name, null)
}

output "bgp_cloud_router_name" {
  value = try(module.gcp[0].bgp_cloud_router_name, null)
}

output "bgp_ncc_hub_name" {
  value = try(module.gcp[0].bgp_ncc_hub_name, null)
}

output "bgp_ncc_spoke_prefix" {
  value = try(module.gcp[0].bgp_ncc_spoke_prefix, null)
}

output "bgp_local_asn" {
  value = try(module.gcp[0].bgp_local_asn, null)
}

output "bgp_router_node_selector_key" {
  value = try(module.gcp[0].bgp_router_node_selector_key, null)
}

output "bgp_router_node_selector_value" {
  value = try(module.gcp[0].bgp_router_node_selector_value, null)
}

output "bgp_gcp_service_account_email" {
  value       = try(module.gcp_bgp_operator_iam[0].gcp_service_account_email, null)
  description = "GCP SA for bgp-cloud-connector CCO (SERVICE_ACCOUNT_EMAIL)."
}

output "bgp_gcp_project_number" {
  value       = local.is_osd_gcp && var.gcp_enable_bgp ? local.gcp_project_number : null
  description = "GCP project number (PROJECT_NUMBER on operator Deployment)."
}

output "bgp_wif_pool_id" {
  value       = local.is_osd_gcp && var.gcp_enable_bgp ? local.wif_pool_id : null
  description = "OCM workload identity pool ID (POOL_ID)."
}

output "bgp_wif_provider_id" {
  value       = local.is_osd_gcp && var.gcp_enable_bgp ? local.wif_provider_id : null
  description = "WIF OIDC provider ID (PROVIDER_ID, typically oidc)."
}

output "bgp_wif_kubernetes_token_audience" {
  value       = local.is_osd_gcp ? local.wif_kubernetes_token_audience : null
  description = "Projected SA token audience; must match OCM WIF provider allowedAudiences."
}