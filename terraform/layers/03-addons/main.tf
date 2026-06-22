terraform {
  required_version = ">= 1.5"
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.40" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.27" }
    helm       = { source = "hashicorp/helm", version = "~> 2.12" }
    kubectl    = { source = "gavinbunney/kubectl", version = "~> 1.14" }
  }

}

locals {
  cluster_auth = {
    host                   = data.terraform_remote_state.platform.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.platform.outputs.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "aws" {
  region = var.aws_region
  default_tags { tags = var.tags }
}

provider "kubernetes" {
  host                   = local.cluster_auth.host
  cluster_ca_certificate = local.cluster_auth.cluster_ca_certificate
  token                  = local.cluster_auth.token
}

provider "helm" {
  kubernetes {
    host                   = local.cluster_auth.host
    cluster_ca_certificate = local.cluster_auth.cluster_ca_certificate
    token                  = local.cluster_auth.token
  }
}

provider "kubectl" {
  host                   = local.cluster_auth.host
  cluster_ca_certificate = local.cluster_auth.cluster_ca_certificate
  token                  = local.cluster_auth.token
  load_config_file       = false
}

module "addons" {
  source = "../../modules/addons"

  cluster_name                = data.terraform_remote_state.platform.outputs.cluster_name
  cluster_endpoint            = data.terraform_remote_state.platform.outputs.cluster_endpoint
  oidc_provider_arn           = data.terraform_remote_state.platform.outputs.oidc_provider_arn
  oidc_provider_url           = data.terraform_remote_state.platform.outputs.cluster_oidc_issuer_url
  vpc_id                      = data.terraform_remote_state.foundation.outputs.vpc_id
  aws_region                  = var.aws_region
  account_id                  = data.aws_caller_identity.current.account_id
  ecr_api_service_repo        = var.ecr_api_service_repo
  ecr_worker_service_repo     = var.ecr_worker_service_repo
  cluster_autoscaler_role_arn = data.terraform_remote_state.platform.outputs.worker_service_role_arn
}

# --- Namespaces ---
resource "kubernetes_namespace" "argocd" {
  metadata { name = "argocd" }
}
resource "kubernetes_namespace" "api_service" {
  metadata { name = "api-service" }
}
resource "kubernetes_namespace" "worker_service" {
  metadata { name = "worker-service" }
}
resource "kubernetes_namespace" "monitoring" {
  metadata { name = "monitoring" }
}

# --- Helm Releases ---
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.3"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  depends_on = [module.addons]

  # Add your specific 'set' blocks here
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.1.3"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  depends_on = [module.addons]

  # Add your specific 'set' blocks here
}
