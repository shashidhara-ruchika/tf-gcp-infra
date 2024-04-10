provider "google" {
  credentials = file(var.credentials_file_path)
  project     = var.project_id
}

provider "google-beta" {
  credentials = file(var.credentials_file_path)
  project     = var.project_id
}

resource "google_service_account" "service_account" {
  account_id                   = var.service_account.account_id
  display_name                 = var.service_account.display_name
  create_ignore_already_exists = var.service_account.create_ignore_already_exists
}

resource "google_project_iam_binding" "service_account_logging_admin" {
  project = var.project_id
  role    = var.roles.logging_admin_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_project_iam_binding" "service_account_monitoring_metric_writer" {
  project = var.project_id
  role    = var.roles.monitoring_metric_writer_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_project_iam_binding" "service_account_pubsub_publisher" {
  project = var.project_id
  role    = var.roles.pubsub_publisher_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_pubsub_topic_iam_binding" "verify_email_topic_binding" {
  project = google_pubsub_topic.verify_email_topic.project
  topic   = google_pubsub_topic.verify_email_topic.name
  role    = var.roles.pubsub_publisher_role
  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account, google_pubsub_topic.verify_email_topic]
}

resource "google_project_iam_binding" "service_account_token_creator_role" {
  project = var.project_id
  role    = var.roles.service_account_token_creator_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_project_iam_binding" "cloud_functions_developer_role" {
  project = var.project_id
  role    = var.roles.cloud_functions_developer_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_project_iam_binding" "cloud_run_invoker_role" {
  project = var.project_id
  role    = var.roles.cloud_run_invoker_role

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]

  depends_on = [google_service_account.service_account]
}

resource "google_cloud_run_service_iam_member" "cloud_run_invoker" {
  count    = var.replica
  project  = google_cloudfunctions2_function.function[count.index].project
  location = google_cloudfunctions2_function.function[count.index].location
  service  = google_cloudfunctions2_function.function[count.index].name
  role     = var.roles.cloud_run_invoker_role
  member   = "serviceAccount:${google_service_account.service_account.email}"

  depends_on = [google_cloudfunctions2_function.function, google_service_account.service_account]
}

resource "google_compute_network" "vpc" {
  count                           = var.replica
  name                            = "${var.vpc.name}-${count.index}"
  auto_create_subnetworks         = var.vpc.auto_create_subnetworks
  routing_mode                    = var.vpc.routing_mode
  delete_default_routes_on_create = var.vpc.delete_default_routes
}

resource "google_compute_subnetwork" "webapp" {
  count         = var.replica
  name          = "${var.vpc_subnet_webapp.name}-${count.index}"
  ip_cidr_range = var.vpc_subnet_webapp.ip_cidr_range
  network       = google_compute_network.vpc[count.index].self_link
  region        = var.region

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_subnetwork" "db" {
  count                    = var.replica
  name                     = "${var.vpc_subnet_db.name}-${count.index}"
  ip_cidr_range            = var.vpc_subnet_db.ip_cidr_range
  network                  = google_compute_network.vpc[count.index].self_link
  region                   = var.region
  private_ip_google_access = var.vpc_subnet_db.enable_private_ip_google_access

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_route" "webapp_route" {
  count            = var.replica
  name             = "${var.vpc_webapp_route.name}-${count.index}-route"
  network          = google_compute_network.vpc[count.index].self_link
  dest_range       = var.vpc_webapp_route.dest_range
  next_hop_gateway = var.vpc_webapp_route.next_hop_gateway

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_global_address" "private_ip_address" {
  count         = var.replica
  name          = "${var.private_ip_address.name}-${count.index}"
  address_type  = var.private_ip_address.global_address_address_type
  purpose       = var.private_ip_address.global_address_purpose
  network       = google_compute_network.vpc[count.index].self_link
  prefix_length = var.private_ip_address.global_address_prefix_length

  depends_on = [google_compute_network.vpc]
}

resource "google_service_networking_connection" "private_vpc_connection" {
  count                   = var.replica
  network                 = google_compute_network.vpc[count.index].self_link
  service                 = var.private_vpc_connection.google_service_nw_connection_service
  reserved_peering_ranges = [google_compute_global_address.private_ip_address[count.index].name]

  depends_on = [google_compute_network.vpc, google_compute_global_address.private_ip_address]
}

resource "google_vpc_access_connector" "serverless_connector" {
  count          = var.replica
  name           = "${var.serverless_vpc_access.name}-${count.index}"
  ip_cidr_range  = var.serverless_vpc_access.ip_cidr_range
  network        = google_compute_network.vpc[count.index].self_link
  machine_type   = var.serverless_vpc_access.machine_type
  min_instances  = var.serverless_vpc_access.minimum_instances
  max_instances  = var.serverless_vpc_access.maximum_instances
  max_throughput = var.serverless_vpc_access.maximum_throughput
  region         = var.region

  depends_on = [google_compute_network.vpc, google_service_networking_connection.private_vpc_connection]
}
resource "google_compute_firewall" "allow_iap" {
  count   = var.replica
  name    = "allow-iap-${count.index}"
  network = google_compute_network.vpc[count.index].name

  allow {
    protocol = var.firewall_allow.firewall_allow_protocol
    ports    = var.firewall_allow.firewall_allow_ports
  }

  source_ranges = [var.vpc_webapp_route.dest_range]
  target_tags   = [var.compute_engine.compute_engine_webapp_tag]

  priority = var.firewall_allow.firewall_allow_priority

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_firewall" "deny_all" {
  count   = var.replica
  name    = "deny-all-${count.index}"
  network = google_compute_network.vpc[count.index].name

  deny {
    protocol = "all"
  }

  source_ranges = [var.vpc_webapp_route.dest_range]
  target_tags   = [var.compute_engine.compute_engine_webapp_tag]

  priority = var.firewall_deny.firewall_deny_priority

  depends_on = [google_compute_network.vpc]
}

resource "google_compute_firewall" "allow_load_balancer" {
  count   = var.replica
  name    = "load-balancer-firewall-${count.index}"
  network = google_compute_network.vpc[count.index].name

  allow {
    protocol = var.firewall_load_balancer_allow.firewall_load_balancer_allow_protocol
    ports    = var.firewall_load_balancer_allow.firewall_load_balancer_allow_ports
  }

  source_ranges = var.firewall_load_balancer_allow.source_ranges
  target_tags   = [var.compute_engine.compute_engine_webapp_tag]

  priority = var.firewall_load_balancer_allow.firewall_load_balancer_allow_priority

  depends_on = [google_compute_network.vpc]

}

resource "google_compute_managed_ssl_certificate" "webapp_ssl_certificate" {
  name = "webapp-ssl-certificate"

  managed {
    domains = [var.dns_record.domain_name]
  }
}

resource "google_compute_global_address" "webapp_forward_address" {
  count   = var.replica
  project = var.project_id
  name    = "webapp-forward-address-${count.index}"
}

resource "google_dns_record_set" "dns_record" {
  count        = var.replica
  name         = var.dns_record.domain_name
  managed_zone = var.dns_record.managed_zone_dns_name
  ttl          = var.dns_record.ttl
  type         = var.dns_record.type
  # rrdatas      = [google_compute_instance.webapp_instance[count.index].network_interface[0].access_config[0].nat_ip]
  rrdatas = [google_compute_global_address.webapp_forward_address[count.index].address]

  # depends_on = [google_compute_instance.webapp_instance]
  depends_on = [google_compute_global_address.webapp_forward_address, google_compute_region_instance_template.webapp_instance_template]
}

# resource "google_compute_instance" "webapp_instance" {
#   count        = var.replica
#   name         = "webapp-instance-${count.index}"
#   machine_type = var.compute_engine.compute_engine_machine_type
#   zone         = var.compute_engine.compute_engine_machine_zone

#   boot_disk {
#     initialize_params {
#       image = var.compute_engine.boot_disk_image
#       type  = var.compute_engine.boot_disk_type
#       size  = var.compute_engine.boot_disk_size
#     }
#   }

#   network_interface {
#     network    = google_compute_network.vpc[count.index].self_link
#     subnetwork = google_compute_subnetwork.webapp[count.index].self_link

#     access_config {

#     }

#   }

#   allow_stopping_for_update = var.compute_engine.compute_engine_allow_stopping_for_update

#   service_account {
#     email  = google_service_account.service_account.email
#     scopes = var.compute_engine.compute_engine_service_account_scopes
#   }

#   tags       = [var.compute_engine.compute_engine_webapp_tag]
#   depends_on = [google_compute_subnetwork.webapp, google_compute_firewall.allow_iap, google_compute_firewall.deny_all, google_sql_database.webapp_db, google_sql_user.webapp_db_user, google_project_iam_binding.service_account_logging_admin, google_project_iam_binding.service_account_monitoring_metric_writer, google_pubsub_topic.verify_email_topic, google_pubsub_subscription.verify_email_subscription, google_vpc_access_connector.serverless_connector]

#   metadata_startup_script = "#!/bin/bash\ncd /opt/csye6225/webapp\nsed -i \"s/DATABASE_NAME=.*/DATABASE_NAME=${var.database.database_name}/\" .env\nsed -i \"s/DATABASE_USER=.*/DATABASE_USER=${var.database.database_user}/\" .env\nsed -i \"s/DATABASE_PASSWORD=.*/DATABASE_PASSWORD=${random_password.webapp_db_password.result}/\" .env\nsed -i \"s/DATABASE_HOST=.*/DATABASE_HOST=${google_sql_database_instance.webapp_cloudsql_instance.ip_address.0.ip_address}/\" .env\nsudo systemctl daemon-reload\nsudo systemctl restart webapp\nsudo systemctl daemon-reload\n"

# }

resource "google_compute_region_instance_template" "webapp_instance_template" {
  count          = var.replica
  name           = "webapp-instance-template-${count.index}"
  machine_type   = var.compute_engine.compute_engine_machine_type
  region         = var.region
  can_ip_forward = var.compute_engine.can_ip_forward

  disk {
    source_image = var.compute_engine.boot_disk_image
    disk_size_gb = var.compute_engine.boot_disk_size
    disk_type    = var.compute_engine.boot_disk_type
    auto_delete  = var.compute_engine.disk_auto_delete
    boot         = var.compute_engine.boot_disk
    disk_encryption_key {
      kms_key_self_link = google_kms_crypto_key.vm_crypto_key.id
    }
  }

  reservation_affinity {
    type = var.compute_engine.reservation_affinity_type
  }

  network_interface {
    network    = google_compute_network.vpc[count.index].self_link
    subnetwork = google_compute_subnetwork.webapp[count.index].self_link
    access_config {

    }
  }

  scheduling {
    automatic_restart = var.compute_engine.scheduling_automatic_restart
    preemptible       = var.compute_engine.scheduling_preemptible
  }

  service_account {
    email  = google_service_account.service_account.email
    scopes = var.compute_engine.compute_engine_service_account_scopes
  }

  labels = {
    gce-service-proxy = "on"
  }

  tags = [var.compute_engine.compute_engine_webapp_tag]

  metadata_startup_script = "#!/bin/bash\ncd /opt/csye6225/webapp\nsed -i \"s/DATABASE_NAME=.*/DATABASE_NAME=${var.database.database_name}/\" .env\nsed -i \"s/DATABASE_USER=.*/DATABASE_USER=${var.database.database_user}/\" .env\nsed -i \"s/DATABASE_PASSWORD=.*/DATABASE_PASSWORD=${random_password.webapp_db_password.result}/\" .env\nsed -i \"s/DATABASE_HOST=.*/DATABASE_HOST=${google_sql_database_instance.webapp_cloudsql_instance.ip_address.0.ip_address}/\" .env\nsudo systemctl daemon-reload\nsudo systemctl restart webapp\nsudo systemctl daemon-reload\n"

  depends_on = [google_compute_subnetwork.webapp, google_compute_firewall.allow_iap, google_compute_firewall.deny_all, google_sql_database.webapp_db, google_sql_user.webapp_db_user, google_project_iam_binding.service_account_logging_admin, google_project_iam_binding.service_account_monitoring_metric_writer, google_pubsub_topic.verify_email_topic, google_pubsub_subscription.verify_email_subscription, google_vpc_access_connector.serverless_connector, google_kms_crypto_key.vm_crypto_key]
}

resource "google_sql_database_instance" "webapp_cloudsql_instance" {
  name                = var.database.name
  database_version    = var.database.database_version
  region              = var.database.region
  deletion_protection = var.database.deletion_protection
  root_password       = var.database.root_password
  encryption_key_name = google_kms_crypto_key.cloudsql_crypto_key.id

  settings {
    tier              = var.database.tier
    availability_type = var.database.availability_type
    disk_type         = var.database.disk_type
    disk_size         = var.database.disk_size

    dynamic "ip_configuration" {
      for_each = google_compute_network.vpc
      iterator = vpc
      content {
        ipv4_enabled                                  = var.database.ipv4_enabled
        private_network                               = vpc.value.self_link
        enable_private_path_for_google_cloud_services = var.database.enabled_private_path
      }
    }

  }

  depends_on = [google_compute_network.vpc, google_service_networking_connection.private_vpc_connection, google_pubsub_subscription.verify_email_subscription, google_pubsub_topic_iam_binding.verify_email_topic_binding, google_kms_crypto_key.cloudsql_crypto_key]
}

resource "google_sql_database" "webapp_db" {
  name     = var.database.database_name
  instance = google_sql_database_instance.webapp_cloudsql_instance.name

  depends_on = [google_sql_database_instance.webapp_cloudsql_instance]
}

resource "random_password" "webapp_db_password" {
  length           = var.database.password_length
  special          = var.database.password_includes_special
  override_special = var.database.password_override_special
}

resource "google_sql_user" "webapp_db_user" {
  name     = var.database.database_user
  instance = google_sql_database_instance.webapp_cloudsql_instance.name
  password = random_password.webapp_db_password.result

  depends_on = [google_sql_database_instance.webapp_cloudsql_instance, random_password.webapp_db_password]
}

resource "google_pubsub_schema" "verify_email_schema" {
  name       = var.pubsub_verify_email.schema.name
  type       = var.pubsub_verify_email.schema.type
  definition = var.pubsub_verify_email.schema.definition
}

resource "google_pubsub_topic" "verify_email_topic" {
  project                    = var.project_id
  name                       = var.pubsub_verify_email.topic.name
  message_retention_duration = var.pubsub_verify_email.topic.message_retention_duration

  schema_settings {
    schema   = "projects/${var.project_id}/schemas/${google_pubsub_schema.verify_email_schema.name}"
    encoding = var.pubsub_verify_email.topic.schema_settings_encoding
  }

  depends_on = [google_pubsub_schema.verify_email_schema]
}

resource "google_pubsub_subscription" "verify_email_subscription" {
  name  = var.pubsub_verify_email.subscription.name
  topic = google_pubsub_topic.verify_email_topic.name

  depends_on = [google_pubsub_topic.verify_email_topic]
}

resource "google_cloudfunctions2_function" "function" {
  count       = var.replica
  project     = var.project_id
  name        = "${var.cloud_function.name}-${count.index}"
  location    = var.region
  description = var.cloud_function.description

  build_config {
    runtime     = var.cloud_function.build_config.runtime
    entry_point = var.cloud_function.build_config.entry_point
    # environment_variables = {
    #   BUILD_CONFIG_TEST = "build_test"
    # }
    source {
      storage_source {
        bucket = google_storage_bucket.webapp_bucket.name
        object = google_storage_bucket_object.serverless_zip.name
      }
    }
  }

  service_config {
    timeout_seconds = var.cloud_function.service_config.timeout_seconds
    environment_variables = {
      MAILGUN_API_KEY             = var.cloud_function.service_config.environment_variables.MAILGUN_API_KEY
      MAILGUN_DOMAIN              = var.cloud_function.service_config.environment_variables.MAILGUN_DOMAIN
      MAILGUN_FROM                = var.cloud_function.service_config.environment_variables.MAILGUN_FROM
      VERIFY_EMAIL_LINK           = var.cloud_function.service_config.environment_variables.VERIFY_EMAIL_LINK
      DATABASE_NAME               = var.database.database_name
      DATABASE_USER               = var.database.database_user
      DATABASE_PASSWORD           = random_password.webapp_db_password.result
      DATABASE_HOST               = google_sql_database_instance.webapp_cloudsql_instance.ip_address.0.ip_address
      VERIFY_EMAIL_EXPIRY_SECONDS = var.cloud_function.service_config.environment_variables.VERIFY_EMAIL_EXPIRY_SECONDS
    }
    available_memory                 = var.cloud_function.service_config.available_memory
    max_instance_request_concurrency = var.cloud_function.service_config.max_instance_request_concurrency
    min_instance_count               = var.cloud_function.service_config.min_instance_count
    max_instance_count               = var.cloud_function.service_config.max_instance_count
    available_cpu                    = var.cloud_function.service_config.available_cpu
    ingress_settings                 = var.cloud_function.service_config.ingress_settings

    vpc_connector = google_vpc_access_connector.serverless_connector[count.index].name

    vpc_connector_egress_settings  = var.cloud_function.service_config.vpc_connector_egress_settings
    service_account_email          = google_service_account.service_account.email
    all_traffic_on_latest_revision = var.cloud_function.service_config.all_traffic_on_latest_revision
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = var.cloud_function.event_trigger.event_type
    pubsub_topic          = "projects/${var.project_id}/topics/${google_pubsub_topic.verify_email_topic.name}"
    retry_policy          = var.cloud_function.event_trigger.retry_policy
    service_account_email = google_service_account.service_account.email
  }

  depends_on = [google_sql_database_instance.webapp_cloudsql_instance, google_pubsub_topic.verify_email_topic, google_storage_bucket_object.serverless_zip, google_vpc_access_connector.serverless_connector]
}

resource "google_compute_health_check" "webapp_health_check" {
  name                = "webapp-health-check"
  check_interval_sec  = var.health_check.check_interval_sec
  timeout_sec         = var.health_check.timeout_sec
  healthy_threshold   = var.health_check.healthy_threshold
  unhealthy_threshold = var.health_check.unhealthy_threshold

  http_health_check {
    port         = var.health_check.port
    port_name    = var.health_check.port_name
    request_path = var.health_check.request_path
  }
}

resource "google_compute_region_instance_group_manager" "webapp_instance_group_manager" {
  count              = var.replica
  name               = "${var.webapp_instance_group_manager.name}-${count.index}"
  base_instance_name = var.webapp_instance_group_manager.base_instance_name
  description        = var.webapp_instance_group_manager.description
  region             = var.region
  version {
    instance_template = google_compute_region_instance_template.webapp_instance_template[count.index].self_link
  }

  distribution_policy_target_shape = var.webapp_instance_group_manager.distribution_policy_target_shape
  distribution_policy_zones        = var.webapp_instance_group_manager.distribution_policy_zones

  named_port {
    name = var.health_check.port_name
    port = var.health_check.port
  }

  auto_healing_policies {
    initial_delay_sec = var.webapp_instance_group_manager.auto_healing_policy_inital_delay_sec
    health_check      = google_compute_health_check.webapp_health_check.self_link
  }

  lifecycle {
    create_before_destroy = true
  }

  # instance_lifecycle_policy {
  #   default_action_on_failure = var.webapp_instance_group_manager.default_action_on_failure
  # }

  depends_on = [google_compute_region_instance_template.webapp_instance_template, google_compute_health_check.webapp_health_check]
}

resource "google_compute_backend_service" "webapp_load_balancer" {
  count = var.replica
  name  = "${var.load_balancer.name}-${count.index}"

  backend {
    group           = google_compute_region_instance_group_manager.webapp_instance_group_manager[count.index].instance_group
    balancing_mode  = var.load_balancer.balancing_mode
    capacity_scaler = var.load_balancer.capacity_scaler
  }

  health_checks = [google_compute_health_check.webapp_health_check.self_link]

  protocol              = var.load_balancer.protocol
  port_name             = var.load_balancer.port_name
  load_balancing_scheme = var.load_balancer.load_balancing_scheme
  timeout_sec           = var.load_balancer.timeout_sec
  enable_cdn            = var.load_balancer.enable_cdn
  # locality_lb_policy    = var.load_balancer.locality_lb_policy

  depends_on = [google_compute_region_instance_group_manager.webapp_instance_group_manager, google_compute_health_check.webapp_health_check]
}

resource "google_compute_url_map" "webapp_url_map" {
  count           = var.replica
  name            = "webapp-url-map"
  default_service = google_compute_backend_service.webapp_load_balancer[count.index].self_link

  depends_on = [google_compute_backend_service.webapp_load_balancer]
}

resource "google_compute_region_autoscaler" "webapp_autoscaler" {
  count  = var.replica
  name   = "${var.auto_scaler.name}-${count.index}"
  target = google_compute_region_instance_group_manager.webapp_instance_group_manager[count.index].id
  region = var.region
  autoscaling_policy {
    max_replicas    = var.auto_scaler.max_repliacs
    min_replicas    = var.auto_scaler.min_replicas
    cooldown_period = var.auto_scaler.cooldown_period
    cpu_utilization {
      target = var.auto_scaler.cpu_utilization_target
    }
    # load_balancing_utilization {
    #   target = 0.8
    # }
  }

  depends_on = [google_compute_region_instance_group_manager.webapp_instance_group_manager]
}

resource "google_compute_target_https_proxy" "webapp_https_proxy" {
  count = var.replica
  name  = "webapp-https-proxy-${count.index}"

  url_map = google_compute_url_map.webapp_url_map[count.index].id

  ssl_certificates = [
    google_compute_managed_ssl_certificate.webapp_ssl_certificate.id
  ]

  depends_on = [google_compute_managed_ssl_certificate.webapp_ssl_certificate, google_compute_url_map.webapp_url_map]
}

resource "google_compute_global_forwarding_rule" "webapp_forwarding_rule" {
  count                 = var.replica
  name                  = "${var.webapp_forwarding_rule.name}-${count.index}"
  ip_protocol           = var.webapp_forwarding_rule.ip_protocol
  load_balancing_scheme = var.webapp_forwarding_rule.load_balancing_scheme
  port_range            = var.webapp_forwarding_rule.port_range
  target                = google_compute_target_https_proxy.webapp_https_proxy[count.index].id
  ip_address            = google_compute_global_address.webapp_forward_address[count.index].id

  depends_on = [google_compute_target_https_proxy.webapp_https_proxy]
}

resource "google_project_service_identity" "sqladmin_service_identity_account" {
  provider = google-beta
  project  = var.project_id
  service  = var.sqladmin_service_identity_account_service
}

resource "random_string" "key_ring_name" {
  length  = var.key_ring.length
  special = var.key_ring.special_characters
}

resource "google_kms_key_ring" "webapp_key_ring" {
  project  = var.project_id
  location = var.region
  name     = "${var.key_ring.name}-${random_string.key_ring_name.result}"

  lifecycle {
    prevent_destroy = false
  }

  depends_on = [random_string.key_ring_name]
}
resource "google_kms_crypto_key" "vm_crypto_key" {
  name            = "vm_crypto_key"
  key_ring        = google_kms_key_ring.webapp_key_ring.id
  rotation_period = var.key_ring.rotation_period
  lifecycle {
    prevent_destroy = false
  }

  depends_on = [google_kms_key_ring.webapp_key_ring]
}
resource "google_kms_crypto_key" "cloudsql_crypto_key" {
  name            = "cloudsql_crypto_key"
  key_ring        = google_kms_key_ring.webapp_key_ring.id
  rotation_period = var.key_ring.rotation_period
  lifecycle {
    prevent_destroy = false
  }

  depends_on = [google_kms_key_ring.webapp_key_ring]
}
resource "google_kms_crypto_key" "cloudstorage_crypto_key" {
  name            = "cloudstorage_crypto_key"
  key_ring        = google_kms_key_ring.webapp_key_ring.id
  rotation_period = var.key_ring.rotation_period
  lifecycle {
    prevent_destroy = false
  }

  depends_on = [google_kms_key_ring.webapp_key_ring]
}
resource "google_kms_crypto_key_iam_binding" "vm_binding" {
  crypto_key_id = google_kms_crypto_key.vm_crypto_key.id
  role          = var.roles.crypto_key_encrypter_decrypter
  members       = ["serviceAccount:${var.service_agents.compute_engine_service_agent}"]

  depends_on = [google_kms_crypto_key.vm_crypto_key]
}
resource "google_kms_crypto_key_iam_binding" "cloudsql_binding" {
  crypto_key_id = google_kms_crypto_key.cloudsql_crypto_key.id
  role          = var.roles.crypto_key_encrypter_decrypter
  members       = ["serviceAccount:${google_project_service_identity.sqladmin_service_identity_account.email}"]

  depends_on = [google_kms_crypto_key.cloudsql_crypto_key]
}
resource "google_kms_crypto_key_iam_binding" "cloudstorage_binding" {
  crypto_key_id = google_kms_crypto_key.cloudstorage_crypto_key.id
  role          = var.roles.crypto_key_encrypter_decrypter
  members       = ["serviceAccount:${var.service_agents.cloud_storage_service_agent}"]

  depends_on = [google_kms_crypto_key.cloudstorage_crypto_key]
}

resource "google_storage_bucket" "webapp_bucket" {
  name          = var.cloud_function.build_config.source_bucket
  location      = var.region
  force_destroy = var.bucket.force_destroy

  public_access_prevention = var.bucket.public_access_prevention
  encryption {
    default_kms_key_name = google_kms_crypto_key.cloudstorage_crypto_key.id
  }

  depends_on = [google_kms_crypto_key.cloudstorage_crypto_key, google_kms_crypto_key_iam_binding.cloudstorage_binding]
}
resource "google_storage_bucket_object" "serverless_zip" {
  name   = var.cloud_function.build_config.source_object
  bucket = google_storage_bucket.webapp_bucket.name
  source = var.bucket.source

  depends_on = [google_storage_bucket.webapp_bucket]
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
  description = "The region to deploy the resources."
  type        = string
}

variable "replica" {
  description = "The number of replicas to deploy."
  type        = number
}

variable "vpc_subnet_webapp" {
  description = "values for webapp subnet"
  type = object({
    name          = string
    ip_cidr_range = string

  })
}

variable "vpc_subnet_db" {
  description = "values for db subnet"
  type = object({
    name                            = string
    ip_cidr_range                   = string
    enable_private_ip_google_access = bool
  })
}

variable "vpc" {
  description = "values for vpc"
  type = object({
    name                    = string
    auto_create_subnetworks = bool
    delete_default_routes   = bool
    routing_mode            = string
  })

}

variable "vpc_webapp_route" {
  description = "values for webapp route"
  type = object({
    name             = string
    dest_range       = string
    next_hop_gateway = string

  })

}

variable "private_ip_address" {
  description = "values for private ip address"
  type = object({
    name                         = string
    global_address_address_type  = string
    global_address_purpose       = string
    global_address_prefix_length = number
  })
}

variable "private_vpc_connection" {
  description = "values for private vpc connection"
  type = object({
    google_service_nw_connection_service = string
  })
}

variable "serverless_vpc_access" {
  description = "values for serverless vpc access"
  type = object({
    name               = string
    ip_cidr_range      = string
    machine_type       = string
    minimum_instances  = number
    maximum_instances  = number
    maximum_throughput = number
  })
}

variable "firewall_allow" {
  description = "values for firewall allow"
  type = object({
    firewall_allow_protocol = string
    firewall_allow_ports    = list(string)
    firewall_allow_priority = number
  })
}

variable "firewall_deny" {
  description = "values for firewall allow"
  type = object({
    firewall_deny_priority = number
  })
}

variable "firewall_load_balancer_allow" {
  description = "values for load balancer firewall allow"
  type = object({
    firewall_load_balancer_allow_protocol = string
    firewall_load_balancer_allow_ports    = list(string)
    firewall_load_balancer_allow_priority = number
    source_ranges                         = list(string)
  })
}
variable "compute_engine" {
  description = "values for compute engine"
  type = object({
    compute_engine_webapp_tag                = string
    compute_engine_machine_type              = string
    compute_engine_machine_zone              = string
    boot_disk_image                          = string
    boot_disk_type                           = string
    boot_disk_size                           = number
    compute_engine_allow_stopping_for_update = bool
    compute_engine_service_account_scopes    = list(string)
    can_ip_forward                           = bool
    disk_auto_delete                         = bool
    boot_disk                                = bool
    reservation_affinity_type                = string
    scheduling_automatic_restart             = bool
    scheduling_preemptible                   = bool
  })
}

variable "dns_record" {
  description = "values for dns record"
  type = object({
    domain_name           = string
    managed_zone_dns_name = string
    ttl                   = number
    type                  = string
  })
}

variable "database" {
  description = "values for database"
  type = object({
    name                      = string
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
}

variable "service_account" {
  description = "Service account variables"
  type = object({
    account_id                   = string
    display_name                 = string
    create_ignore_already_exists = bool
  })

}


variable "service_agents" {
  description = "Service account variables"
  type = object({
    compute_engine_service_agent = string
    cloud_storage_service_agent  = string
  })

}
variable "roles" {
  description = "Project Iam Binding Roles"
  type = object({
    logging_admin_role            = string
    monitoring_metric_writer_role = string

    pubsub_publisher_role              = string
    service_account_token_creator_role = string

    cloud_functions_developer_role = string
    cloud_run_invoker_role         = string

    artifact_registry_create_on_push_writer = string
    storage_object_admin_role               = string
    logs_writer_role                        = string

    crypto_key_encrypter_decrypter = string
  })
}

variable "pubsub_verify_email" {
  description = "PubSub verify email variables"
  type = object({
    schema = object({
      name       = string
      type       = string
      definition = string
    })
    topic = object({
      name                       = string
      message_retention_duration = string
      schema_settings_encoding   = string
    })
    subscription = object({
      name = string
    })
  })
}

variable "cloud_function" {
  description = "Cloud Function variables"
  type = object({
    name        = string
    description = string

    build_config = object({
      entry_point   = string
      runtime       = string
      source_bucket = string
      source_object = string
    })

    service_config = object({
      environment_variables = object({
        MAILGUN_API_KEY             = string
        MAILGUN_DOMAIN              = string
        MAILGUN_FROM                = string
        VERIFY_EMAIL_LINK           = string
        VERIFY_EMAIL_EXPIRY_SECONDS = string
      })
      timeout_seconds                  = number
      available_memory                 = string
      max_instance_request_concurrency = number
      min_instance_count               = number
      max_instance_count               = number
      available_cpu                    = number
      ingress_settings                 = string
      vpc_connector_egress_settings    = string
      all_traffic_on_latest_revision   = bool
    })

    event_trigger = object({
      event_type   = string
      resource     = string
      retry_policy = string
    })
  })
}

variable "health_check" {
  description = "Health Check variables"
  type = object({
    name                = string
    check_interval_sec  = number
    timeout_sec         = number
    healthy_threshold   = number
    unhealthy_threshold = number
    port_name           = string
    request_path        = string
    port                = string

  })

}

variable "webapp_instance_group_manager" {
  description = "Webapp Instance Group Manager variables"
  type = object({
    name                                 = string
    base_instance_name                   = string
    description                          = string
    distribution_policy_zones            = list(string)
    distribution_policy_target_shape     = string
    life_cycle_create_before_destroy     = bool
    auto_healing_policy_inital_delay_sec = number
    force_update_on_repair               = string
    default_action_on_failure            = string

  })
}

variable "load_balancer" {
  description = "Load Balancer variables"
  type = object({
    name                  = string
    protocol              = string
    port_name             = string
    load_balancing_scheme = string
    timeout_sec           = number
    enable_cdn            = bool
    balancing_mode        = string
    capacity_scaler       = number
    locality_lb_policy    = string
  })
}

variable "auto_scaler" {
  description = "Auto Scaler variables"
  type = object({
    name                   = string
    max_repliacs           = number
    min_replicas           = number
    cooldown_period        = number
    cpu_utilization_target = number
  })

}

variable "webapp_forwarding_rule" {
  description = "Webapp Forwarding Rule variables"
  type = object({
    name                  = string
    ip_protocol           = string
    load_balancing_scheme = string
    port_range            = string
  })
}

variable "ssl_certificates" {
  description = "The SSL certificates to use for the load balancer."
  type        = list(string)
}


variable "sqladmin_service_identity_account_service" {
  description = "The service account email for the sqladmin service account."
  type        = string
}

variable "key_ring" {
  description = "The key ring to create."
  type = object({
    name                      = string
    length                    = number
    special_characters        = bool
    lifecycle_prevent_destroy = bool
    rotation_period           = string
  })

}


variable "bucket" {
  description = "The bucket to create."
  type = object({
    force_destroy            = bool
    public_access_prevention = string
    source                   = string
  })
}
