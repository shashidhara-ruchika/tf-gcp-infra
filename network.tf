provider "google" {
  credentials = file(var.credentials_file_path)
  project     = var.project_id
  region      = var.region
}

# Loop through the list of VPC configurations and create VPCs
resource "google_compute_network" "vpc" {
  count                           = length(var.vpcs)
  name                            = var.vpcs[count.index].vpc_name
  auto_create_subnetworks         = var.vpcs[count.index].vpc_auto_create_subnetworks
  routing_mode                    = var.vpcs[count.index].vpc_routing_mode
  delete_default_routes_on_create = var.vpcs[count.index].vpc_delete_default_routes_on_create
}

resource "google_compute_subnetwork" "webapp" {
  count         = length(var.vpcs)
  name          = var.vpcs[count.index].vpc_subnet_webapp_name
  ip_cidr_range = var.vpcs[count.index].vpc_subnet_webapp_ip_cidr_range
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.region
}

resource "google_compute_subnetwork" "db" {
  count         = length(var.vpcs)
  name          = var.vpcs[count.index].vpc_subnet_db_name
  ip_cidr_range = var.vpcs[count.index].vpc_subnet_db_ip_cidr_range
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.region
}

resource "google_compute_route" "webapp_route" {
  count            = length(var.vpcs)
  name             = "webapp-route-${count.index}"
  network          = google_compute_network.vpc[count.index].self_link
  dest_range       = var.vpcs[count.index].vpc_dest_range
  next_hop_gateway = var.vpcs[count.index].vpc_next_hop_gateway
  priority         = var.vpc_route_webapp_route_priority
}

# Define a variable to store VPC configurations
variable "vpcs" {
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

variable "region" {
  description = "The region where resources will be deployed."
  type        = string
}

variable "vpc_route_webapp_route_priority" {
  description = "The priority for the web application route."
  type        = number
}
