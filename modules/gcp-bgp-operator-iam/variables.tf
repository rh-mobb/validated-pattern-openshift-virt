variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "project_number_for_wif_principal" {
  type        = string
  description = "GCP project number in WIF principal paths (from platform.json eso.wif_provider_resource_name)."
}

variable "workload_identity_pool_id" {
  type        = string
  description = "OCM workload identity pool ID (platform wif_config_id)."
}

variable "workload_identity_provider_id" {
  type        = string
  description = "OIDC provider ID on the pool (typically oidc)."
}

variable "kubernetes_namespace" {
  type        = string
  default     = "openshift-bgp-cloud-connector"
  description = "Namespace of the bgp-cloud-connector manager ServiceAccount."
}

variable "kubernetes_service_account_name" {
  type        = string
  default     = "openshift-bgp-cloud-connector-controller-manager"
  description = "Kubernetes ServiceAccount for WIF impersonation binding."
}

variable "service_account_id" {
  type        = string
  description = "GCP service account_id (short name, max 30 characters)."
}

variable "service_account_display_name" {
  type        = string
  default     = "BGP Cloud Connector operator"
  description = "Display name for the GCP service account."
}

variable "custom_role_id" {
  type        = string
  description = "Project custom role id (role_id segment, not full resource name)."
}

variable "custom_role_title" {
  type        = string
  default     = "BGP Cloud Connector"
  description = "Human title for the custom IAM role."
}