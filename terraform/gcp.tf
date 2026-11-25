module "gcp" {
  count  = local.is_osd_gcp ? 1 : 0
  source = "../modules/gcp"

  cluster_name                              = local.platform.cluster_name
  gcp_project_id                            = local.platform.gcp_project_id
  gcp_region                                = local.platform.gcp_region
  storage_zone                              = local.gcp_storage_zone
  storage_pool_name                         = var.gcp_storage_pool_name
  storage_class_name                        = var.gcp_storage_class_name
  enable_hyperdisk_pool                     = var.gcp_enable_hyperdisk_pool
  storage_pool_capacity_gb                  = var.gcp_storage_pool_capacity_gb
  storage_pool_provisioned_iops             = var.gcp_storage_pool_provisioned_iops
  storage_pool_provisioned_throughput_mibps = var.gcp_storage_pool_provisioned_throughput_mibps
  vpc_name                                  = try(local.platform.network.vpc_name, "")
  worker_subnet_name                        = try(local.platform.network.compute_subnet, "")

  enable_bgp                          = var.gcp_enable_bgp
  cloud_router_asn                    = var.gcp_bgp_cloud_router_asn
  bgp_local_asn                       = var.gcp_bgp_local_asn
  bgp_interface_host_offset           = var.gcp_bgp_interface_host_offset
  router_interface_private_ips        = var.gcp_bgp_router_interface_private_ips
  reserve_cloud_router_interface_ips  = var.gcp_bgp_reserve_router_interface_ips
  cudn_cidr                           = var.gcp_bgp_cudn_cidr
  worker_subnet_to_cudn_firewall_mode = var.gcp_bgp_worker_to_cudn_firewall_mode
  routing_worker_target_tags          = var.gcp_bgp_routing_worker_target_tags
  bgp_router_node_selector_key        = var.gcp_bgp_router_node_selector_key
  bgp_router_node_selector_value      = var.gcp_bgp_router_node_selector_value
}