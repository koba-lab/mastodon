terraform {
  required_providers {
    conoha = {
      source = "sacloud/conoha"
      version = "~> 1.0"
    }
  }
  required_version = ">= 1.0.0"
  
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "conoha" {
  user_name     = var.conoha_user_name
  tenant_name   = var.conoha_tenant_name
  password      = var.conoha_password
  auth_url      = var.conoha_auth_url
  region        = var.conoha_region
}

module "postgresql_server" {
  source = "../../modules/postgresql_server"
  
  environment         = "production"
  image_id            = var.image_id
  flavor_id           = var.flavor_id
  network_id          = var.network_id
  private_network_cidr = var.private_network_cidr
  ssh_key_name        = var.ssh_key_name
  server_name_prefix  = "pg16-prod"
}

output "postgresql_new_ip" {
  value = module.postgresql_server.postgresql_new_ip
}

output "postgresql_new_private_ip" {
  value = module.postgresql_server.postgresql_new_private_ip
}
