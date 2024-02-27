provider "google" {
  credentials = file(var.credentials_file_path)
  project     = var.project_id
}

resource "google_compute_network" "vpc" {
  count                           = length(var.iaac)
  name                            = var.iaac[count.index].vpc_name
  auto_create_subnetworks         = var.iaac[count.index].vpc_auto_create_subnetworks
  routing_mode                    = var.iaac[count.index].vpc_routing_mode
  delete_default_routes_on_create = var.iaac[count.index].vpc_delete_default_routes_on_create
}

resource "google_compute_subnetwork" "webapp" {
  count         = length(var.iaac)
  name          = var.iaac[count.index].vpc_subnet_webapp_name
  ip_cidr_range = var.iaac[count.index].vpc_subnet_webapp_ip_cidr_range
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.iaac[count.index].region
}

resource "google_compute_subnetwork" "db" {
  count         = length(var.iaac)
  name          = var.iaac[count.index].vpc_subnet_db_name
  ip_cidr_range = var.iaac[count.index].vpc_subnet_db_ip_cidr_range
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.iaac[count.index].region
}

resource "google_compute_route" "webapp_route" {
  count            = length(var.iaac)
  name             = "webapp-route-${count.index}"
  network          = google_compute_network.vpc[count.index].self_link
  dest_range       = var.iaac[count.index].vpc_dest_range
  next_hop_gateway = var.iaac[count.index].vpc_next_hop_gateway
  priority         = var.iaac[count.index].vpc_route_webapp_route_priority
}

resource "google_compute_firewall" "allow_iap" {
  count   = length(var.iaac)
  name    = "allow-iap-${count.index}"
  network = google_compute_network.vpc[count.index].name

  allow {
    protocol = var.iaac[count.index].firewall_allow_protocol
    ports    = var.iaac[count.index].firewall_allow_ports
  }

  source_ranges = [var.iaac[count.index].vpc_dest_range]
  target_tags   = [var.iaac[count.index].compute_engine_webapp_tag]

  priority = var.iaac[count.index].firewall_allow_priority
}

resource "google_compute_firewall" "deny_all" {
  count   = length(var.iaac)
  name    = "deny-all-${count.index}"
  network = google_compute_network.vpc[count.index].name

  deny {
    protocol = "all"
  }

  source_ranges = [var.iaac[count.index].vpc_dest_range]
  target_tags   = [var.iaac[count.index].compute_engine_webapp_tag]

  priority = var.iaac[count.index].firewall_deny_priority
}

resource "google_compute_instance" "webapp_instance" {
  count        = length(var.iaac)
  name         = "webapp-instance-${count.index}"
  machine_type = var.iaac[count.index].compute_engine_machine_type
  zone         = var.iaac[count.index].compute_engine_machine_zone

  boot_disk {
    initialize_params {
      image = var.iaac[count.index].boot_disk_image
      type  = var.iaac[count.index].boot_disk_type
      size  = var.iaac[count.index].boot_disk_size
    }
  }

  network_interface {
    network    = google_compute_network.vpc[count.index].self_link
    subnetwork = google_compute_subnetwork.webapp[count.index].self_link
    access_config {

    }

  }

  tags       = [var.iaac[count.index].compute_engine_webapp_tag]
  depends_on = [google_compute_subnetwork.webapp, google_compute_firewall.allow_iap, google_compute_firewall.deny_all]

}

variable "iaac" {
  type = list(object({
    vpc_name                            = string
    vpc_subnet_webapp_name              = string
    vpc_subnet_webapp_ip_cidr_range     = string
    vpc_subnet_db_name                  = string
    vpc_subnet_db_ip_cidr_range         = string
    vpc_routing_mode                    = string
    vpc_dest_range                      = string
    vpc_auto_create_subnetworks         = bool
    vpc_delete_default_routes_on_create = bool
    vpc_next_hop_gateway                = string
    vpc_route_webapp_route_priority     = number
    region                              = string
    compute_engine_webapp_tag           = string
    compute_engine_machine_type         = string
    compute_engine_machine_zone         = string
    boot_disk_image                     = string
    boot_disk_type                      = string
    boot_disk_size                      = number
    firewall_allow_protocol             = string
    firewall_allow_ports                = list(string)
    firewall_allow_priority             = string
    firewall_deny_priority              = string
  }))
}

variable "credentials_file_path" {
  description = "The path to the service account key file."
  type        = string
}

variable "project_id" {
  description = "The ID of the Google Cloud Platform project."
  type        = string
}
