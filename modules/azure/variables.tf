variable "cluster_name" {
  description = "Cluster name used for ANF account, pool, subnet, and identity names."
  type        = string
}

variable "resource_group_name" {
  description = "Customer resource group that already holds the cluster VNet."
  type        = string
}

variable "location" {
  type = string
}

variable "vnet_name" {
  type = string
}

variable "subnet_prefix" {
  description = "Delegated ANF subnet CIDR (installer reserved default 10.0.3.0/24)."
  type        = string
}

variable "subnet_name" {
  description = "ANF delegated subnet name. Defaults to <cluster_name>-netapp."
  type        = string
  default     = null
  nullable    = true
}

variable "oidc_issuer_url" {
  description = "Cluster OIDC issuer for the Trident federated credential. Empty skips the credential."
  type        = string
  default     = ""
}

variable "trident_federated_subject" {
  description = "Federated credential subject (Trident controller ServiceAccount)."
  type        = string
  default     = "system:serviceaccount:trident:trident-controller"
}

variable "pool_size_tib" {
  description = "ANF capacity pool size in TiB (Flexible minimum is 1)."
  type        = number
  default     = 1
}

variable "service_level" {
  description = "ANF capacity pool service level."
  type        = string
  default     = "Flexible"
}

variable "custom_throughput_mibps" {
  description = "Required for Flexible + Manual QoS. Azure minimum is 128 MiB/s."
  type        = number
  default     = 128
}

variable "route_server_subnet_prefix" {
  description = "Installer-reserved CIDR for Azure Route Server (subnet must be named RouteServerSubnet, /26 or larger)."
  type        = string
}

variable "bgp_router_pool_names" {
  description = "platform.json node pool names that have labels.bgp_router = true."
  type        = list(string)
}

variable "bgp_federated_subject" {
  description = "Federated credential subject for the bgp-cloud-connector manager ServiceAccount."
  type        = string
  default     = "system:serviceaccount:openshift-bgp-cloud-connector:openshift-bgp-cloud-connector-controller-manager"
}

variable "network_interface_client_id" {
  description = "Installer cluster-api-azure client ID (BGPCloudConfiguration spec.azure.networkInterfaceClientID). Empty fails apply."
  type        = string
  default     = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
