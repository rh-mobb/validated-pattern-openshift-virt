provider "azurerm" {
  features {}
}

provider "google" {
  project = try(jsondecode(file(var.platform_json)).gcp_project_id, "unused-azure-only")
  region  = try(jsondecode(file(var.platform_json)).gcp_region, "us-central1")
}
