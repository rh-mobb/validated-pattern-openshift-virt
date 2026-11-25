locals {
  platform = jsondecode(file(var.platform_json))

  is_osd_gcp = try(local.platform.installer, "") == "osd-gcp"

  _node_pools = merge(
    try(local.platform.node_pools, {}),
    try(local.platform.machine_pools, {}),
  )
  bgp_router_pool_names = [
    for name, p in local._node_pools : name
    if tostring(try(p.labels["bgp_router"], "")) == "true"
  ]

  # Classic machine-api, then HCP cluster-api-azure. Empty fails the Azure BGP precondition.
  network_interface_client_id = (
    trimspace(try(local.platform.machine_api_client_id, "")) != "" ?
    trimspace(try(local.platform.machine_api_client_id, "")) :
    trimspace(try(local.platform.cluster_api_azure_client_id, ""))
  )

  # Prefer explicit virt_storage_zone in platform.json; else override; else region-a.
  # try() keeps Azure platform.json without gcp_region from failing plan.
  gcp_storage_zone = coalesce(
    try(local.platform.virt_storage_zone, null),
    var.gcp_storage_zone_override != "" ? var.gcp_storage_zone_override : null,
    try("${local.platform.gcp_region}-a", null),
    "unspecified",
  )
}