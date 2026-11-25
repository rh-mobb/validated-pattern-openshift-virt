# GCP cloud slice: Hyperdisk zonal storage pool (google_compute_storage_pool).
# In-cluster StorageClass, VSC, and StorageProfile RWX: GitOps osd-gcp overlay (hyperdisk + cnv jobs).

locals {
  storage_pool_path = var.enable_hyperdisk_pool ? (
    "projects/${var.gcp_project_id}/zones/${var.storage_zone}/storagePools/${google_compute_storage_pool.virt[0].name}"
  ) : "projects/${var.gcp_project_id}/zones/${var.storage_zone}/storagePools/${var.storage_pool_name}"
}