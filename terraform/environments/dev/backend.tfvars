terraform {
  backend "s3" {
    bucket         = "eks-gitops-platform-tfstate-962765734677"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}