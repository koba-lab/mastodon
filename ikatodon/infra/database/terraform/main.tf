terraform {
  required_providers {
    conoha = {
      source = "sacloud/conoha"
      version = "~> 1.0"
    }
  }
  required_version = ">= 1.0.0"
}

provider "conoha" {
  user_name     = var.conoha_user_name
  tenant_name   = var.conoha_tenant_name
  password      = var.conoha_password
  auth_url      = var.conoha_auth_url
  region        = var.conoha_region
}

resource "conoha_server" "postgresql_new" {
  name            = "pg16-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  image_id        = var.image_id
  flavor_id       = var.flavor_id
  security_groups = ["default", "postgresql"]
  user_data       = file("${path.module}/cloud-init.yml")
  
  network {
    uuid = var.network_id
  }
  
  tags = {
    role = "postgresql"
    version = "16"
    environment = var.environment
  }
}

resource "conoha_security_group" "postgresql" {
  name        = "postgresql"
  description = "Allow PostgreSQL inbound traffic"
}

resource "conoha_security_group_rule" "postgresql" {
  security_group_id = conoha_security_group.postgresql.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_ip_prefix  = var.private_network_cidr
}

resource "conoha_security_group_rule" "ssh" {
  security_group_id = conoha_security_group.postgresql.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
}

output "postgresql_new_ip" {
  value = conoha_server.postgresql_new.access_ipv4
}

output "postgresql_new_private_ip" {
  value = conoha_server.postgresql_new.network[0].fixed_ip_v4
}
