variable "conoha_user_name" {
  description = "ConoHa APIユーザー名"
  type        = string
}

variable "conoha_tenant_name" {
  description = "ConoHaテナント名"
  type        = string
}

variable "conoha_password" {
  description = "ConoHa APIパスワード"
  type        = string
  sensitive   = true
}

variable "conoha_auth_url" {
  description = "ConoHa認証URL"
  type        = string
  default     = "https://identity.tyo1.conoha.io/v2.0"
}

variable "conoha_region" {
  description = "ConoHaリージョン"
  type        = string
  default     = "tyo1"
}

variable "image_id" {
  description = "使用するOSイメージID"
  type        = string
  default     = "ubuntu-20.04-amd64" # Ubuntu 20.04 LTS
}

variable "flavor_id" {
  description = "VPSプラン"
  type        = string
  default     = "g-2gb" # 2GB RAM
}

variable "network_id" {
  description = "ネットワークID"
  type        = string
}

variable "private_network_cidr" {
  description = "プライベートネットワークCIDR"
  type        = string
  default     = "192.168.0.0/24"
}

variable "environment" {
  description = "環境名"
  type        = string
  default     = "production"
}
