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
  # private_ip_google_access = var.iaac[count.index].vpc_subnet_private_ip_google_access

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_subnetwork" "db" {
  count                    = length(var.iaac)
  name                     = var.iaac[count.index].vpc_subnet_db_name
  ip_cidr_range            = var.iaac[count.index].vpc_subnet_db_ip_cidr_range
  network                  = google_compute_network.vpc[count.index].self_link
  region                   = var.iaac[count.index].region
  private_ip_google_access = var.iaac[count.index].vpc_subnet_private_ip_google_access

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_route" "webapp_route" {
  count            = length(var.iaac)
  name             = "webapp-route-${count.index}"
  network          = google_compute_network.vpc[count.index].self_link
  dest_range       = var.iaac[count.index].vpc_dest_range
  next_hop_gateway = var.iaac[count.index].vpc_next_hop_gateway
  priority         = var.iaac[count.index].vpc_route_webapp_route_priority

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_global_address" "private_ip_address" {
  count         = length(var.iaac)
  name          = "private-ip-address-${count.index}"
  address_type  = "INTERNAL"
  purpose       = "VPC_PEERING"
  network       = google_compute_network.vpc[count.index].self_link
  prefix_length = 24
  # address      = "10.0.2.3"

  depends_on = [google_compute_network.vpc]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = length(var.iaac)
  network                 = google_compute_network.vpc[count.index].self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address[count.index].name]

  depends_on = [google_compute_network.vpc, google_compute_global_address.private_ip_address]
}

locals {
  count                     = length(var.iaac)
  current_timestamp_seconds = formatdate("YYYYMMDDhhmmss", timestamp())
}

resource "google_sql_database_instance" "webapp_cloudsql_instance" {
  count               = length(var.iaac)
  name                = "webapp-cloudsql-${local.current_timestamp_seconds}"
  database_version    = var.iaac[count.index].database.database_version
  region              = var.iaac[count.index].database.region
  deletion_protection = var.iaac[count.index].database.deletion_protection
  root_password       = var.iaac[count.index].database.root_password

  settings {
    tier              = var.iaac[count.index].database.tier
    availability_type = var.iaac[count.index].database.availability_type
    disk_type         = var.iaac[count.index].database.disk_type
    disk_size         = var.iaac[count.index].database.disk_size


    ip_configuration {
      ipv4_enabled                                  = var.iaac[count.index].database.ipv4_enabled
      private_network                               = google_compute_network.vpc[count.index].self_link
      enable_private_path_for_google_cloud_services = var.iaac[count.index].database.enabled_private_path
    }
  }

  depends_on = [google_compute_network.vpc, google_service_networking_connection.private_vpc_connection]
}

resource "google_sql_database" "webapp_db" {
  count    = length(var.iaac)
  name     = var.iaac[count.index].database.database_name
  instance = google_sql_database_instance.webapp_cloudsql_instance[count.index].name

  depends_on = [google_sql_database_instance.webapp_cloudsql_instance]
}

resource "random_password" "webapp_db_password" {
  count            = length(var.iaac)
  length           = var.iaac[count.index].database.password_length
  special          = var.iaac[count.index].database.password_includes_special
  override_special = var.iaac[count.index].database.password_override_special
}

resource "google_sql_user" "webapp_db_user" {
  count    = length(var.iaac)
  name     = var.iaac[count.index].database.database_user
  instance = google_sql_database_instance.webapp_cloudsql_instance[count.index].name
  password = random_password.webapp_db_password[count.index].result

  depends_on = [google_sql_database_instance.webapp_cloudsql_instance, random_password.webapp_db_password]
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

  depends_on = [google_compute_network.vpc]
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

  depends_on = [google_compute_network.vpc]
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
  depends_on = [google_compute_subnetwork.webapp, google_compute_firewall.allow_iap, google_compute_firewall.deny_all, google_sql_database.webapp_db, google_sql_user.webapp_db_user]

  metadata_startup_script = "#!/bin/bash\ncd /opt/csye6225/webapp\nsed -i \"s/DATABASE_NAME=.*/DATABASE_NAME=${var.iaac[count.index].database.database_name}/\" .env\nsed -i \"s/DATABASE_USER=.*/DATABASE_USER=${var.iaac[count.index].database.database_user}/\" .env\nsed -i \"s/DATABASE_PASSWORD=.*/DATABASE_PASSWORD=${random_password.webapp_db_password[count.index].result}/\" .env\nsed -i \"s/DATABASE_HOST=.*/DATABASE_HOST=${google_sql_database_instance.webapp_cloudsql_instance[count.index].ip_address.0.ip_address}/\" .env\nsudo systemctl daemon-reload\nsudo systemctl restart webapp\nsudo systemctl daemon-reload\n"

}

variable "credentials_file_path" {
  description = "The path to the service account key file."
  type        = string
}

variable "project_id" {
  description = "The ID of the Google Cloud Platform project."
  type        = string
}

variable "iaac" {
  description = "Infra as code variables"
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
    vpc_subnet_private_ip_google_access = bool
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
    database = object({
      database_version          = string
      region                    = string
      deletion_protection       = bool
      tier                      = string
      availability_type         = string
      disk_type                 = string
      disk_size                 = number
      ipv4_enabled              = bool
      enabled_private_path      = bool
      database_name             = string
      password_length           = number
      password_includes_special = bool
      password_override_special = string
      database_user             = string
      root_password             = string
    })
  }))
}

variable "database" {
  description = "Database variables"
  type = object({
    database_version          = string
    region                    = string
    deletion_protection       = bool
    tier                      = string
    availability_type         = string
    disk_type                 = string
    disk_size                 = number
    ipv4_enabled              = bool
    enabled_private_path      = bool
    database_name             = string
    password_length           = number
    password_includes_special = bool
    password_override_special = string
    database_user             = string
  })
}
