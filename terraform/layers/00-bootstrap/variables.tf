variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_org" {
  type    = string
  default = "Lumbenlengo"
}

variable "github_repo" {
  type    = string
  default = "eks-gitops-platform"
}

variable "tags" {
  type = map(string)
  default = {
    Project     = "eks-gitops-platform"
    ManagedBy   = "terraform"
    Owner       = "Lumbenlengo"
    Environment = "prod"
    Layer       = "00-bootstrap"
  }
}
