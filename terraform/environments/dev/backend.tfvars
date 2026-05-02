terraform {
  backend "s3" {
    bucket         = "lt-lumbe-tfstate-962765734677"
    key            = "eks-gitops-platform/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}