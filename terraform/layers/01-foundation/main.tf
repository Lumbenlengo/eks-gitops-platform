provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.tags
  }
}

module "networking" {
  source = "../../modules/networking"

  cluster_name    = var.cluster_name
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
  # Use the data source defined in data.tf
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  enable_nat_gateway     = false
  single_nat_gateway     = false
  one_nat_gateway_per_az = false
}
