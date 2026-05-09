output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value     = module.eks.cluster_endpoint
  sensitive = true
}

output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

output "cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "api_service_role_arn" {
  value = module.irsa.api_service_role_arn
}

output "worker_service_role_arn" {
  value = module.irsa.worker_service_role_arn
}

output "sqs_queue_url" {
  value = module.irsa.sqs_queue_url
}

output "sqs_queue_arn" {
  value = module.irsa.sqs_queue_arn
}

output "dynamodb_table_name" {
  value = module.irsa.dynamodb_table_name
}

output "configure_kubectl" {
  value = "aws eks update-kubeconfig --region us-east-1 --name ${module.eks.cluster_name}"
}
