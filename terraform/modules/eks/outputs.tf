output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  value = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.eks.arn
}

output "node_security_group_id" {
  value = aws_security_group.node.id
}

output "cluster_security_group_id" {
  value = aws_security_group.cluster.id
}

output "node_iam_role_arn" {
  value = aws_iam_role.node.arn
}
