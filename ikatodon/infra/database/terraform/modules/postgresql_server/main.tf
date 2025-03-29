resource "conoha_server" "postgresql_new" {
  name            = "${var.server_name_prefix}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  image_id        = var.image_id
  flavor_id       = var.flavor_id
  security_groups = ["default", conoha_security_group.postgresql.name]
  user_data       = file("${path.module}/cloud-init.yml")
  key_name        = var.ssh_key_name
  
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
  name        = "postgresql-${var.environment}"
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

resource "conoha_security_group_rule" "prometheus" {
  security_group_id = conoha_security_group.postgresql.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 9187
  port_range_max    = 9187
  remote_ip_prefix  = var.private_network_cidr
}

output "postgresql_new_ip" {
  value = conoha_server.postgresql_new.access_ipv4
}

output "postgresql_new_private_ip" {
  value = conoha_server.postgresql_new.network[0].fixed_ip_v4
}
