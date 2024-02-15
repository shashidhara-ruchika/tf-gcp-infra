provider "google" {
  credentials = file(var.credentials_path)
  project     = var.project_id
  region      = var.region
}

resource "google_compute_network" "vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = var.vpc_auto_create_subnetworks
  routing_mode            = var.vpc_routing_mode
  delete_default_routes_on_create = var.vpc_delete_default_routes_on_create
}

resource "google_compute_subnetwork" "webapp" {
  name          = var.vpc_subnet_webapp_name
  ip_cidr_range = var.vpc_subnet_webapp_ip_cidr_range
  network       = google_compute_network.vpc.self_link
}

resource "google_compute_subnetwork" "db" {
  name          = var.vpc_subnet_db_name
  ip_cidr_range = var.vpc_subnet_db_ip_cidr_range
  network       = google_compute_network.vpc.self_link
}

resource "google_compute_route" "webapp_route" {
  name         = var.vpc_route_webapp_route_name
  network      = google_compute_network.vpc.self_link
  dest_range   = var.vpc_route_webapp_route_range
  next_hop_gateway = var.vpc_route_webapp_route_next_hop_gateway
  priority     = var.vpc_route_webapp_route_priority
}



variable "credentials_path" {
  description = "The path to the service account key file."
  type = string
}

variable "project_id" {
  description = "The ID of the Google Cloud Platform project."
  type = string
}

variable "region" {
  description = "The region where resources will be deployed."
  type = string
}



variable "vpc_name" {
  description = "The name of the Virtual Private Cloud (VPC)."
  type = string
}

variable "vpc_auto_create_subnetworks" {
  description = "Whether to auto-create subnetworks in the VPC."
  type        = bool
}

variable "vpc_routing_mode" {
  description = "The routing mode for the VPC."
  type = string
}

variable "vpc_delete_default_routes_on_create" {
  description = "Whether to delete default routes when creating the VPC."
  type        = bool
}



variable "vpc_subnet_webapp_name" {
  description = "The name of the subnet for the web application."
  type = string
}

variable "vpc_subnet_webapp_ip_cidr_range" {
  description = "The IP CIDR range for the web application subnet."
  type = string
}



variable "vpc_subnet_db_name" {
  description = "The name of the subnet for the database."
  type = string
}

variable "vpc_subnet_db_ip_cidr_range" {
  description = "The IP CIDR range for the database subnet."
  type = string
}



variable "vpc_route_webapp_route_name" {
  description = "The name of the route for the web application subnet."
  type = string
}

variable "vpc_route_webapp_route_range" {
  description = "The destination range for the web application route."
  type = string
}

variable "vpc_route_webapp_route_next_hop_gateway" {
  description = "The next hop gateway for the web application route."
  type = string
}

variable "vpc_route_webapp_route_priority" {
  description = "The priority for the web application route."
  type        = number
}
