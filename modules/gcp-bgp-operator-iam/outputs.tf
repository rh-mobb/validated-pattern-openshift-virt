output "gcp_service_account_email" {
  value       = google_service_account.operator.email
  description = "GCP SA email for SERVICE_ACCOUNT_EMAIL / CCO CredentialsRequest."
}

output "workload_identity_principal_member" {
  value       = local.workload_identity_impersonation_member
  description = "principal:// binding for troubleshooting."
}

output "custom_role_id" {
  value       = google_project_iam_custom_role.bgp_cloud_connector.id
  description = "Full custom role resource name."
}