variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-gitops-platform"
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.29"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
}

variable "node_group_instance_types" {
  description = "EC2 instance types for the managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "node_group_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "node_group_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 10
}

variable "ecr_api_service_repo" {
  description = "ECR repository name for the API service"
  type        = string
  default     = "eks-gitops/api-service"
}

variable "ecr_worker_service_repo" {
  description = "ECR repository name for the worker service"
  type        = string
  default     = "eks-gitops/worker-service"
}

variable "sqs_queue_name" {
  description = "Name of the SQS queue for the worker service"
  type        = string
  default     = "eks-gitops-worker-queue"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used by the worker service"
  type        = string
  default     = "eks-gitops-items"
}

variable "argocd_namespace" {
  description = "Kubernetes namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "eks-gitops-platform"
    ManagedBy   = "terraform"
    Owner       = "patriciolumbe"
    Environment = "prod"
  }
}
