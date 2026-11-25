variable "platform_json" {
  description = "Path to installer clusters/<name>/platform.json (make cluster.<name>.platform)."
  type        = string
}

variable "pool_size_tib" {
  type    = number
  default = 1
}

variable "custom_throughput_mibps" {
  description = "Flexible + Manual QoS pool throughput. Azure minimum is 128 MiB/s."
  type        = number
  default     = 128
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "gcp_storage_pool_name" {
  type        = string
  default     = "ocp-virt-pool"
  description = "Zonal Hyperdisk Balanced storage pool name (OSD GCP)."
}

variable "gcp_storage_class_name" {
  type        = string
  default     = "sp-balanced-storage"
  description = "Default virt StorageClass for OSD GCP."
}

variable "gcp_storage_zone_override" {
  type        = string
  default     = ""
  description = "Optional zone when platform.json has no virt_storage_zone (e.g. us-central1-a)."
}

variable "gcp_enable_hyperdisk_pool" {
  type        = bool
  default     = true
  description = "Create google_compute_storage_pool in modules/gcp."
}

variable "gcp_storage_pool_capacity_gb" {
  type    = number
  default = 10240
}

variable "gcp_storage_pool_provisioned_iops" {
  type    = number
  default = 10000
}

variable "gcp_storage_pool_provisioned_throughput_mibps" {
  type    = number
  default = 1024
}

variable "gcp_enable_bgp" {
  type        = bool
  default     = true
  description = "Provision NCC hub + Cloud Router in modules/gcp (BGP/CUDN lab)."
}

variable "gcp_bgp_cloud_router_asn" {
  type        = number
  default     = 64512
  description = "BGP ASN on the dedicated Cloud Router (not cluster NAT router)."
}

variable "gcp_bgp_local_asn" {
  type        = number
  default     = 65001
  description = "Local ASN for BGPCloudConfiguration / FRR speakers."
}

variable "gcp_bgp_interface_host_offset" {
  type        = number
  default     = 230
  description = "cidrhost offset for Cloud Router interface IPs in the worker subnet."
}

variable "gcp_bgp_router_interface_private_ips" {
  type        = list(string)
  default     = null
  description = "Optional fixed /32 pair for Cloud Router interfaces."
}

variable "gcp_bgp_reserve_router_interface_ips" {
  type        = bool
  default     = true
  description = "Reserve internal GCE_ENDPOINT addresses for router interfaces."
}

variable "gcp_bgp_cudn_cidr" {
  type        = string
  default     = "192.168.100.0/24"
  description = "CUDN CIDR for worker-subnet ingress firewall (must match BGPRouting subnets)."
}

variable "gcp_bgp_worker_to_cudn_firewall_mode" {
  type        = string
  default     = "e2etest"
  description = "Worker to CUDN firewall: all, e2etest, or none."
}

variable "gcp_bgp_routing_worker_target_tags" {
  type        = list(string)
  default     = []
  description = "Optional GCP network tags for BGP/CUDN firewall scoping."
}

variable "gcp_bgp_router_node_selector_key" {
  type        = string
  default     = "workload"
  description = "Node label key for BGP speaker pool (osd-gcp lab: workload=nested-lab)."
}

variable "gcp_bgp_router_node_selector_value" {
  type        = string
  default     = "nested-lab"
  description = "Node label value for BGP speaker pool."
}
