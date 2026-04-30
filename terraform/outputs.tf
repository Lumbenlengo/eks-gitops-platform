output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
  sensitive   = true
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the cluster"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL used for IRSA"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "api_service_irsa_role_arn" {
  description = "IAM role ARN for the API service (IRSA)"
  value       = module.irsa.api_service_role_arn
}

output "worker_service_irsa_role_arn" {
  description = "IAM role ARN for the worker service (IRSA)"
  value       = module.irsa.worker_service_role_arn
}

output "sqs_queue_url" {
  description = "URL of the SQS queue consumed by the worker service"
  value       = module.irsa.sqs_queue_url
}

output "sqs_queue_arn" {
  description = "ARN of the SQS queue"
  value       = module.irsa.sqs_queue_arn
}

output "dynamodb_table_name" {
  description = "DynamoDB table name used by the worker service"
  value       = module.irsa.dynamodb_table_name
}

output "ecr_api_service_url" {
  description = "ECR repository URL for the API service image"
  value       = module.addons.ecr_api_service_url
}

output "ecr_worker_service_url" {
  description = "ECR repository URL for the worker service image"
  value       = module.addons.ecr_worker_service_url
}

output "configure_kubectl" {
  description = "Run this command to configure kubectl access to the cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
