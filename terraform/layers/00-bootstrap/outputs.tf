

output "tflock_table" {
  value = aws_dynamodb_table.tflock.name
}

output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "terraform_role_arn" {
  value = aws_iam_role.github_terraform.arn
}

output "ecr_push_role_arn" {
  value = aws_iam_role.github_ecr_push.arn
}
