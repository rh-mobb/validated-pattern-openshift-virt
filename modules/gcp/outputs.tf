output "gcp_project_id" {
  value = var.gcp_project_id
}

output "gcp_region" {
  value = var.gcp_region
}

output "storage_zone" {
  value = var.storage_zone
}

output "storage_pool_name" {
  value = var.storage_pool_name
}

output "storage_pool_path" {
  value = local.storage_pool_path
}

output "storage_class_name" {
  value = var.storage_class_name
}

output "cluster_name" {
  value = var.cluster_name
}

output "bgp_cloud_router_name" {
  value = var.enable_bgp ? local.cloud_router_name : ""
}

output "bgp_ncc_hub_name" {
  value = var.enable_bgp ? local.ncc_hub_name : ""
}

output "bgp_ncc_spoke_prefix" {
  value = var.enable_bgp ? local.ncc_spoke_prefix : ""
}

output "bgp_local_asn" {
  value = tostring(var.bgp_local_asn)
}

output "bgp_router_node_selector_key" {
  value = var.bgp_router_node_selector_key
}

output "bgp_router_node_selector_value" {
  value = var.bgp_router_node_selector_value
}

output "bgp_cloud_router_asn" {
  value = var.cloud_router_asn
}

output "bgp_cloud_router_interface_ips" {
  value = var.enable_bgp ? [
    google_compute_router_interface.primary[0].private_ip_address,
    google_compute_router_interface.redundant[0].private_ip_address,
  ] : []
}