data "google_compute_network" "vpc" {
  count   = var.enable_bgp ? 1 : 0
  name    = var.vpc_name
  project = var.gcp_project_id
}

data "google_compute_subnetwork" "worker" {
  count   = var.enable_bgp ? 1 : 0
  name    = var.worker_subnet_name
  region  = var.gcp_region
  project = var.gcp_project_id
}