# BGP + CUDN cloud prerequisites for bgp-cloud-connector (GCP platform).
# Ported from validated-pattern osd-gcp-cudn-routing modules/osd-bgp-routing.

locals {
  vpc_self_link      = var.enable_bgp ? data.google_compute_network.vpc[0].self_link : null
  worker_subnet_link = var.enable_bgp ? data.google_compute_subnetwork.worker[0].self_link : null

  router_private_ips = var.enable_bgp ? (
    var.router_interface_private_ips != null ? var.router_interface_private_ips : [
      cidrhost(data.google_compute_subnetwork.worker[0].ip_cidr_range, var.bgp_interface_host_offset),
      cidrhost(data.google_compute_subnetwork.worker[0].ip_cidr_range, var.bgp_interface_host_offset + 1),
    ]
  ) : []

  worker_subnet_v4 = var.enable_bgp ? regex(
    "^([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})/([0-9]{1,2})$",
    data.google_compute_subnetwork.worker[0].ip_cidr_range,
  ) : null

  worker_subnet_v4_prefix_len = var.enable_bgp ? parseint(local.worker_subnet_v4[4], 10) : 0
  worker_subnet_v4_net_u32 = var.enable_bgp ? (
    parseint(local.worker_subnet_v4[0], 10) * 16777216
    + parseint(local.worker_subnet_v4[1], 10) * 65536
    + parseint(local.worker_subnet_v4[2], 10) * 256
    + parseint(local.worker_subnet_v4[3], 10)
  ) : 0
  worker_subnet_v4_size = var.enable_bgp ? pow(2, 32 - local.worker_subnet_v4_prefix_len) : 0

  router_private_ip_v4_u32 = [
    for ip in local.router_private_ips : (
      parseint(regex("^([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})$", ip)[0], 10) * 16777216
      + parseint(regex("^([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})$", ip)[1], 10) * 65536
      + parseint(regex("^([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})$", ip)[2], 10) * 256
      + parseint(regex("^([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})\\.([0-9]{1,3})$", ip)[3], 10)
    )
  ]

  cloud_router_name = var.enable_bgp ? "${var.cluster_name}-cudn-cr" : ""
  ncc_hub_name      = var.enable_bgp ? "${var.cluster_name}-ncc-hub" : ""
  ncc_spoke_prefix  = var.enable_bgp ? "${var.cluster_name}-ra-spoke" : ""

  routing_firewall_target_tags = length(var.routing_worker_target_tags) > 0 ? var.routing_worker_target_tags : null
  worker_subnet_to_cudn_desc = (
    var.worker_subnet_to_cudn_firewall_mode == "none" ? "disabled" :
    var.worker_subnet_to_cudn_firewall_mode == "all" ? "All protocols: worker subnet to CUDN (BGP-learned routes)" :
    "E2E-minimal: ICMP + TCP/8080 from worker subnet to CUDN"
  )
}

check "router_interface_ip_count" {
  assert {
    condition     = !var.enable_bgp || var.router_interface_private_ips == null || length(var.router_interface_private_ips) == 2
    error_message = "router_interface_private_ips must be null or have exactly 2 elements."
  }
}

check "router_interface_ips_in_worker_subnet" {
  assert {
    condition = !var.enable_bgp || alltrue([
      for u32 in local.router_private_ip_v4_u32 :
      u32 >= local.worker_subnet_v4_net_u32 && u32 < local.worker_subnet_v4_net_u32 + local.worker_subnet_v4_size
    ])
    error_message = "Each Cloud Router interface IP must fall within the worker subnetwork primary IPv4 CIDR."
  }
}

resource "google_network_connectivity_hub" "cudn" {
  count       = var.enable_bgp ? 1 : 0
  name        = local.ncc_hub_name
  project     = var.gcp_project_id
  description = "NCC hub for CUDN router appliance (validated-pattern-openshift-virt)"
}

resource "google_compute_router" "cudn" {
  count   = var.enable_bgp ? 1 : 0
  name    = local.cloud_router_name
  project = var.gcp_project_id
  region  = var.gcp_region
  network = local.vpc_self_link

  bgp {
    asn = var.cloud_router_asn
  }
}

resource "google_compute_address" "cloud_router_interface" {
  count = var.enable_bgp && var.reserve_cloud_router_interface_ips ? 2 : 0

  name         = "${var.cluster_name}-cr-if-${count.index}-addr"
  project      = var.gcp_project_id
  region       = var.gcp_region
  subnetwork   = local.worker_subnet_link
  address_type = "INTERNAL"
  purpose      = "GCE_ENDPOINT"
  address      = local.router_private_ips[count.index]
}

resource "google_compute_router_interface" "primary" {
  count   = var.enable_bgp ? 1 : 0
  project = var.gcp_project_id
  region  = var.gcp_region
  name    = "${var.cluster_name}-cr-if-0"
  router  = google_compute_router.cudn[0].name

  subnetwork = local.worker_subnet_link
  private_ip_address = (
    var.reserve_cloud_router_interface_ips
    ? google_compute_address.cloud_router_interface[0].address
    : local.router_private_ips[0]
  )
}

resource "google_compute_router_interface" "redundant" {
  count   = var.enable_bgp ? 1 : 0
  project = var.gcp_project_id
  region  = var.gcp_region
  name    = "${var.cluster_name}-cr-if-1"
  router  = google_compute_router.cudn[0].name

  subnetwork = local.worker_subnet_link
  private_ip_address = (
    var.reserve_cloud_router_interface_ips
    ? google_compute_address.cloud_router_interface[1].address
    : local.router_private_ips[1]
  )
  redundant_interface = google_compute_router_interface.primary[0].name
}

resource "google_compute_firewall" "worker_subnet_to_cudn" {
  count = var.enable_bgp && var.worker_subnet_to_cudn_firewall_mode != "none" ? 1 : 0

  project     = var.gcp_project_id
  name        = "${var.cluster_name}-worker-subnet-to-cudn"
  network     = local.vpc_self_link
  direction   = "INGRESS"
  priority    = 900
  description = local.worker_subnet_to_cudn_desc

  source_ranges      = [data.google_compute_subnetwork.worker[0].ip_cidr_range]
  destination_ranges = [var.cudn_cidr]
  target_tags        = local.routing_firewall_target_tags

  dynamic "allow" {
    for_each = var.worker_subnet_to_cudn_firewall_mode == "all" ? [1] : []
    content {
      protocol = "all"
    }
  }

  dynamic "allow" {
    for_each = var.worker_subnet_to_cudn_firewall_mode == "e2etest" ? [1] : []
    content {
      protocol = "icmp"
    }
  }

  dynamic "allow" {
    for_each = var.worker_subnet_to_cudn_firewall_mode == "e2etest" ? [1] : []
    content {
      protocol = "tcp"
      ports    = ["8080"]
    }
  }
}

resource "google_compute_firewall" "bgp_worker_subnet" {
  count = var.enable_bgp ? 1 : 0

  project     = var.gcp_project_id
  name        = "${var.cluster_name}-bgp-worker-subnet"
  network     = local.vpc_self_link
  direction   = "INGRESS"
  priority    = 900
  description = length(var.routing_worker_target_tags) > 0 ? "BGP tcp/179 scoped to routing_worker_target_tags" : "BGP tcp/179 worker subnet (lab)"

  source_ranges      = [data.google_compute_subnetwork.worker[0].ip_cidr_range]
  destination_ranges = local.routing_firewall_target_tags == null ? [data.google_compute_subnetwork.worker[0].ip_cidr_range] : null
  target_tags        = local.routing_firewall_target_tags

  allow {
    protocol = "tcp"
    ports    = ["179"]
  }
}