terraform {
  backend "s3" {
    bucket         = "lt-lumbe-tfstate-ACCOUNT_ID"
    key            = "eks-gitops-platform/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}