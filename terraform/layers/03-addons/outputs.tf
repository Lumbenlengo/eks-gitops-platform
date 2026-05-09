output "ecr_api_service_url" {
  value = module.addons.ecr_api_service_url
}

output "ecr_worker_service_url" {
  value = module.addons.ecr_worker_service_url
}

output "argocd_namespace" {
  value = kubernetes_namespace.argocd.metadata[0].name
}
