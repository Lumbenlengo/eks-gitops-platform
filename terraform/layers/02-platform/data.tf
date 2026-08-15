data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = "eks-git-ops-platform-tfstate-979054355604"
    key    = "foundation/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}
