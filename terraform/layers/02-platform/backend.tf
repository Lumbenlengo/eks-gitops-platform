terraform {
  backend "s3" {
    bucket         = "eks-git-ops-platform-tfstate-979054355604"
    key            = "platform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "eks-git-ops-platform-tfstate-lock"
    encrypt        = true
  }
}