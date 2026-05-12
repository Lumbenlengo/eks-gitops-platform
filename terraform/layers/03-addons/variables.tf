# AWS Region for the infrastructure
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# ECR Repository for the API Service
variable "ecr_api_service_repo" {
  type    = string
  default = "eks-gitops/api-service"
}

# ECR Repository for the Worker Service
variable "ecr_worker_service_repo" {
  type    = string
  default = "eks-gitops/worker-service"
}

# Resource tagging strategy
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

# Optional variables with defaults to bypass initial validation.
# Values are dynamically injected via remote_state in main.tf.
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