variable "environment" {
  description = "環境名"
  type        = string
  default     = "production"
}

variable "image_id" {
  description = "使用するOSイメージID"
  type        = string
}

variable "flavor_id" {
  description = "VPSプラン"
  type        = string
}

variable "network_id" {
  description = "ネットワークID"
  type        = string
}

variable "private_network_cidr" {
  description = "プライベートネットワークCIDR"
  type        = string
}

variable "ssh_key_name" {
  description = "SSHキー名"
  type        = string
}

variable "server_name_prefix" {
  description = "サーバー名のプレフィックス"
  type        = string
  default     = "pg16"
}
