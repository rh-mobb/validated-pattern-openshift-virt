resource "google_compute_storage_pool" "virt" {
  count   = var.enable_hyperdisk_pool ? 1 : 0
  name    = var.storage_pool_name
  zone    = var.storage_zone
  project = var.gcp_project_id

  storage_pool_type             = "hyperdisk-balanced"
  capacity_provisioning_type    = "ADVANCED"
  performance_provisioning_type = "ADVANCED"
  pool_provisioned_capacity_gb  = var.storage_pool_capacity_gb
  pool_provisioned_iops         = tostring(var.storage_pool_provisioned_iops)
  pool_provisioned_throughput   = tostring(var.storage_pool_provisioned_throughput_mibps)

  deletion_protection = false
}