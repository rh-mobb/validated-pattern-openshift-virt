locals {
  wif_provider_resource = try(local.platform.eso.wif_provider_resource_name, "")

  gcp_project_number = (
    length(regexall("^projects/([0-9]+)/", local.wif_provider_resource)) > 0
    ? regex("^projects/([0-9]+)/", local.wif_provider_resource)[0]
    : null
  )

  wif_pool_id = coalesce(
    try(local.platform.wif_config_id, null),
    length(regexall("workloadIdentityPools/([^/]+)/", local.wif_provider_resource)) > 0
    ? regex("workloadIdentityPools/([^/]+)/", local.wif_provider_resource)[0]
    : null,
  )

  wif_provider_id = (
    length(regexall("providers/([^/]+)$", local.wif_provider_resource)) > 0
    ? regex("providers/([^/]+)$", local.wif_provider_resource)[0]
    : "oidc"
  )

  wif_kubernetes_token_audience = try(local.platform.eso.wif_kubernetes_token_audience, "openshift")

  bgp_operator_sa_id = substr(
    replace(lower("${local.platform.cluster_name}-bgp-cc"), "_", "-"),
    0,
    30,
  )

  bgp_operator_custom_role_id = substr(
    replace(lower("${local.platform.cluster_name}_bgp_cloud_connector"), "-", "_"),
    0,
    64,
  )
}

resource "terraform_data" "bgp_operator_iam_precondition" {
  count = local.is_osd_gcp && var.gcp_enable_bgp ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.gcp_project_number != null && local.wif_pool_id != null && local.wif_pool_id != ""
      error_message = "platform.json must include eso.wif_provider_resource_name and/or wif_config_id for BGP operator WIF."
    }
  }
}

module "gcp_bgp_operator_iam" {
  count  = local.is_osd_gcp && var.gcp_enable_bgp ? 1 : 0
  source = "../modules/gcp-bgp-operator-iam"

  project_id                       = local.platform.gcp_project_id
  project_number_for_wif_principal = local.gcp_project_number
  workload_identity_pool_id        = local.wif_pool_id
  workload_identity_provider_id    = local.wif_provider_id

  service_account_id           = local.bgp_operator_sa_id
  service_account_display_name = "BGP Cloud Connector (${local.platform.cluster_name})"
  custom_role_id               = local.bgp_operator_custom_role_id

  depends_on = [terraform_data.bgp_operator_iam_precondition]
}