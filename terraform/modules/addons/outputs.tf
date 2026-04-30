output "ecr_api_service_url" {
  value = aws_ecr_repository.api_service.repository_url
}

output "ecr_worker_service_url" {
  value = aws_ecr_repository.worker_service.repository_url
}

output "alb_controller_role_arn" {
  value = aws_iam_role.alb_controller.arn
}

output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}

output "keda_role_arn" {
  value = aws_iam_role.keda.arn
}
