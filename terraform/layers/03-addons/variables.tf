variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "ecr_api_service_repo" {
  type    = string
  default = "eks-gitops/api-service"
}
variable "ecr_worker_service_repo" {
  type    = string
  default = "eks-gitops/worker-service"
}
variable "tags" {
  type = map(string)
  default = {
    Project     = "eks-gitops-platform"
    ManagedBy   = "terraform"
    Owner       = "Lumbenlengo"
    Environment = "prod"
    Layer       = "03-addons"
  }
}
variable "cluster_name" {
  type    = string
  default = ""
}
variable "cluster_endpoint" {
  type    = string
  default = ""
}
variable "cluster_ca_cert" {
  type    = string
  default = ""
}
