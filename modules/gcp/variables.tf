variable "cluster_name" {
  type        = string
  description = "OSD cluster name from platform.json."
}

variable "gcp_project_id" {
  type        = string
  description = "GCP project hosting the cluster and Hyperdisk storage pool."
}

variable "gcp_region" {
  type        = string
  description = "GCP region."
}

variable "storage_zone" {
  type        = string
  description = "Zonal Hyperdisk storage pool location (typically same AZ as virt workers)."
}

variable "storage_pool_name" {
  type        = string
  default     = "ocp-virt-pool"
  description = "Name of the zonal Hyperdisk Balanced storage pool (created by scripts/gcp-hyperdisk-storage.sh)."
}

variable "storage_class_name" {
  type        = string
  default     = "sp-balanced-storage"
  description = "StorageClass using pd.csi.storage.gke.io and the storage pool."
}

variable "enable_hyperdisk_pool" {
  type        = bool
  default     = true
  description = "Create google_compute_storage_pool (minimum 10 TiB provisioned capacity)."
}

variable "storage_pool_capacity_gb" {
  type        = number
  default     = 10240
  description = "Hyperdisk pool provisioned capacity in GiB (10240 = 10 TiB minimum for balanced advanced)."
}

variable "storage_pool_provisioned_iops" {
  type    = number
  default = 10000
}

variable "storage_pool_provisioned_throughput_mibps" {
  type    = number
  default = 1024
}

variable "vpc_name" {
  type        = string
  default     = ""
  description = "BYO VPC name from platform.json network.vpc_name (required when enable_bgp)."
}

variable "worker_subnet_name" {
  type        = string
  default     = ""
  description = "Worker subnet name from platform.json network.compute_subnet."
}

variable "enable_bgp" {
  type        = bool
  default     = true
  description = "Provision NCC hub, Cloud Router, and BGP firewall rules for bgp-cloud-connector."
}

variable "cloud_router_asn" {
  type        = number
  default     = 64512
  description = "Cloud Router BGP ASN (RFC 6996 private)."
}

variable "bgp_local_asn" {
  type        = number
  default     = 65001
  description = "Node/local ASN for BGPCloudConfiguration spec.bgp.localASN."
}

variable "bgp_interface_host_offset" {
  type        = number
  default     = 230
  description = "Host index base for Cloud Router interface IPs in the worker subnet CIDR."
}

variable "router_interface_private_ips" {
  type        = list(string)
  default     = null
  description = "Optional explicit private IPs for the two Cloud Router interfaces."
}

variable "reserve_cloud_router_interface_ips" {
  type        = bool
  default     = true
  description = "Reserve GCE_ENDPOINT addresses for Cloud Router interfaces."
}

variable "cudn_cidr" {
  type        = string
  default     = "10.100.0.0/16"
  description = "CUDN prefix in worker-subnet-to-CUDN firewall rule."
}

variable "worker_subnet_to_cudn_firewall_mode" {
  type        = string
  default     = "e2etest"
  description = "Ingress worker→CUDN: all, e2etest, or none."

  validation {
    condition     = contains(["all", "e2etest", "none"], var.worker_subnet_to_cudn_firewall_mode)
    error_message = "worker_subnet_to_cudn_firewall_mode must be all, e2etest, or none."
  }
}

variable "routing_worker_target_tags" {
  type        = list(string)
  default     = []
  description = "Optional network tags scoping BGP/CUDN firewall rules to router nodes."
}

variable "bgp_router_node_selector_key" {
  type        = string
  default     = "workload"
  description = "Node label key for BGP speakers (bgp-cloud-connector routerNodeSelector)."
}

variable "bgp_router_node_selector_value" {
  type        = string
  default     = "nested-lab"
  description = "Node label value for BGP speakers."
}

check "bgp_network_from_platform" {
  assert {
    condition     = !var.enable_bgp || (var.vpc_name != "" && var.worker_subnet_name != "")
    error_message = "enable_bgp requires vpc_name and worker_subnet_name from platform.json network."
  }
}