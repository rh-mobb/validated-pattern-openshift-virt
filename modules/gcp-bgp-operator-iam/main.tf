# GCP SA + OCM WIF pool impersonation for openshift bgp-cloud-connector (CCO external_account path).
# Permissions mirror the operator CredentialsRequest (networking.openshift.io bgp-cloud-connector-gcp).

locals {
  bgp_cloud_connector_permissions = [
    "compute.instances.get",
    "compute.instances.update",
    "compute.networks.get",
    "compute.networks.updatePolicy",
    "compute.regionOperations.get",
    "compute.routers.get",
    "compute.routers.update",
    "compute.zoneOperations.get",
    "networkconnectivity.hubs.get",
    "networkconnectivity.operations.get",
    "networkconnectivity.spokes.create",
    "networkconnectivity.spokes.delete",
    "networkconnectivity.spokes.get",
    "networkconnectivity.spokes.list",
    "networkconnectivity.spokes.update",
  ]

  workload_identity_impersonation_member = format(
    "principal://iam.googleapis.com/projects/%s/locations/global/workloadIdentityPools/%s/subject/system:serviceaccount:%s:%s",
    var.project_number_for_wif_principal,
    var.workload_identity_pool_id,
    var.kubernetes_namespace,
    var.kubernetes_service_account_name,
  )
}

resource "google_project_iam_custom_role" "bgp_cloud_connector" {
  project     = var.project_id
  role_id     = var.custom_role_id
  title       = var.custom_role_title
  description = "Least-privilege GCP APIs for bgp-cloud-connector on OSD WIF (CCO federated credentials)."
  permissions = local.bgp_cloud_connector_permissions
}

resource "google_service_account" "operator" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = var.service_account_display_name
}

resource "google_project_iam_member" "operator_custom_role" {
  project = var.project_id
  role    = google_project_iam_custom_role.bgp_cloud_connector.id
  member  = "serviceAccount:${google_service_account.operator.email}"
}

resource "google_service_account_iam_member" "wif_impersonation" {
  service_account_id = google_service_account.operator.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.workload_identity_impersonation_member
}