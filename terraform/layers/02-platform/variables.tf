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

# --- Infrastructure Variables (Added to resolve warnings) ---

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.0.0.0/16" # Update this to match your environment if needed
}

variable "private_subnets" {
  type        = list(string)
  description = "List of private subnet CIDRs"
  default     = []
}

variable "public_subnets" {
  type        = list(string)
  description = "List of public subnet CIDRs"
  default     = []
}

variable "vpc_id" {
  type        = string
  description = "The VPC ID"
  default     = null
}

# --- Node Group Variables ---

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

# --- Application/Storage Variables ---

variable "sqs_queue_name" {
  type    = string
  default = "order-processing-queue"
}

variable "dynamodb_table_name" {
  type    = string
  default = "order-storage-table"
}

variable "ecr_api_service_repo" {
  type    = string
  default = "api-service"
}

variable "ecr_worker_service_repo" {
  type    = string
  default = "worker-service"
}

# --- Tags ---

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
