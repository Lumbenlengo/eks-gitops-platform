project_name       = "eks-gitops-platform"
environment        = "prod"
region             = "us-east-1"
account_id         = "962765734677"

github_repo        = "Lumbenlengo/eks-gitops-platform"
node_capacity_type = "SPOT"
node_instance_type = "t3.medium"
node_min_size      = 1
node_max_size      = 3
node_desired_size  = 2