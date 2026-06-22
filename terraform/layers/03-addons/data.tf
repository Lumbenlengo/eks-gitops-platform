data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = "eks-gitops-platform-tfstate-962765734677"
    key    = "platform/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = "eks-gitops-platform-tfstate-962765734677"
    key    = "foundation/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.platform.outputs.cluster_name
}