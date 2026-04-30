variable "cluster_name" { type = string }
variable "cluster_endpoint" { type = string }
variable "oidc_provider_arn" { type = string }
variable "oidc_provider_url" { type = string }
variable "vpc_id" { type = string }
variable "aws_region" { type = string }
variable "account_id" { type = string }
variable "ecr_api_service_repo" { type = string }
variable "ecr_worker_service_repo" { type = string }
variable "cluster_autoscaler_role_arn" {
  type    = string
  default = ""
}
