mock_provider "google" {
  alias = "mock"
}

run "storage_without_bgp" {
  command = plan

  providers = {
    google = google.mock
  }

  variables {
    cluster_name          = "virt-lab"
    gcp_project_id        = "test-project"
    gcp_region            = "us-central1"
    storage_zone          = "us-central1-a"
    enable_bgp            = false
    enable_hyperdisk_pool = false
    vpc_name              = ""
    worker_subnet_name    = ""
  }

  assert {
    condition     = output.storage_pool_path == "projects/test-project/zones/us-central1-a/storagePools/ocp-virt-pool"
    error_message = "Hyperdisk pool path must be derived from project, zone, and pool name."
  }

  assert {
    condition     = output.bgp_cloud_router_name == ""
    error_message = "BGP outputs must be empty when enable_bgp is false."
  }
}