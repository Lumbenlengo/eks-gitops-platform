module "eks" {
  source = "../../modules/eks"

  cluster_name              = var.cluster_name
  cluster_version           = var.cluster_version
  vpc_id                    = data.terraform_remote_state.foundation.outputs.vpc_id
  private_subnet_ids        = data.terraform_remote_state.foundation.outputs.private_subnet_ids
  public_subnet_ids         = data.terraform_remote_state.foundation.outputs.public_subnet_ids
  node_group_instance_types = var.node_group_instance_types
  node_group_desired_size   = var.node_group_desired_size
  node_group_min_size       = var.node_group_min_size
  node_group_max_size       = var.node_group_max_size
  account_id                = data.aws_caller_identity.current.account_id
}

module "irsa" {
  source              = "../../modules/irsa"
  cluster_name        = var.cluster_name
  oidc_provider_arn   = module.eks.oidc_provider_arn
  oidc_provider_url   = module.eks.cluster_oidc_issuer_url
  sqs_queue_name      = var.sqs_queue_name
  dynamodb_table_name = var.dynamodb_table_name
  account_id          = data.aws_caller_identity.current.account_id
  aws_region          = var.aws_region
  depends_on          = [module.eks]
}
# Delete this Block:
# resource "aws_eks_access_entry" "github_actions" {
#   cluster_name  = module.eks.cluster_name
#   principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/github-actions-terraform"
#   type          = "STANDARD"
# }

resource "aws_eks_access_policy_association" "github_actions_admin" {
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/github-actions-terraform"

  access_scope {
    type = "cluster"
  }
}