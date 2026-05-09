variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "eks-gitops-platform"
}

variable "cluster_version" {
  type    = string
  default = "1.30"
}

variable "node_group_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_group_desired_size" {
  type    = number
  default = 2
}

variable "node_group_min_size" {
  type    = number
  default = 1
}

variable "node_group_max_size" {
  type    = number
  default = 3
}

variable "sqs_queue_name" {
  type    = string
  default = "order-processing-queue"
}

variable "dynamodb_table_name" {
  type    = string
  default = "order-storage-table"
}

variable "tags" {
  type = map(string)
  default = {
    Project     = "eks-gitops-platform"
    ManagedBy   = "terraform"
    Owner       = "Lumbenlengo"
    Environment = "prod"
    Layer       = "02-platform"
  }
}
