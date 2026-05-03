
# Project Metadata
project_name = "eco-order-system"
environment  = "prod"
region       = "us-east-1"
account_id   = "962765734677"

# EKS Cluster Configuration
cluster_version    = "1.30"
node_capacity_type = "ON_DEMAND"
node_instance_type = "t3.medium"

# Scaling Configuration
node_min_size     = 1
node_desired_size = 2
node_max_size     = 3

# Network Infrastructure
vpc_cidr        = "10.0.0.0/16"
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]

# Application Resources
sqs_queue_name      = "order-processing-queue"
dynamodb_table_name = "order-storage-table"
argocd_namespace    = "argocd"

# Resource Tagging
tags = {
  Project     = "eks-gitops-platform"
  Environment = "prod"
  ManagedBy   = "terraform"
  Owner       = "Patricio-Lumbenlengo"
  Mission     = "Retail-Order-Processor"
}