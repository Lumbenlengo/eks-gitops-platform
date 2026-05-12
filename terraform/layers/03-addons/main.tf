terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
  backend "s3" {}
}

################################################################################
# Remote State
################################################################################

data "terraform_remote_state" "platform" {
  backend = "s3"
  config = {
    bucket = "eks-gitops-platform-tfstate-962765734677"
    key    = "platform/terraform.tfstate"
    region = "us-east-1"
  }
}

data "terraform_remote_state" "foundation" {
  backend = "s3"
  config = {
    bucket = "eks-gitops-platform-tfstate-962765734677"
    key    = "foundation/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_eks_cluster_auth" "this" {
  name = data.terraform_remote_state.platform.outputs.cluster_name
}

data "aws_caller_identity" "current" {}

################################################################################
# Providers
################################################################################

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.tags
  }
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.platform.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.platform.outputs.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.platform.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.platform.outputs.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  host                   = data.terraform_remote_state.platform.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.platform.outputs.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

################################################################################
# Addons Module
################################################################################

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

################################################################################
# ArgoCD
################################################################################

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.3"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  set {
    name  = "configs.secret.argocdServerAdminPassword"
    value = "$2a$10$rRyBsGSHK6.uc8fntPwVIuLVHgsAhAX7TcdrqW/9mu9dS5Pf5CMHK"
  }

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "server.ingress.enabled"
    value = "true"
  }

  set {
    name  = "server.ingress.ingressClassName"
    value = "alb"
  }

  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme"
    value = "internet-facing"
  }

  set {
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type"
    value = "ip"
  }

  set {
    name  = "server.insecure"
    value = "true"
  }

  depends_on = [module.addons]
}

################################################################################
# Application Namespaces
################################################################################

resource "kubernetes_namespace" "api_service" {
  metadata {
    name = "api-service"
    labels = {
      "app.kubernetes.io/managed-by" = "argocd"
    }
  }
}

resource "kubernetes_namespace" "worker_service" {
  metadata {
    name = "worker-service"
    labels = {
      "app.kubernetes.io/managed-by" = "argocd"
    }
  }
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

################################################################################
# Monitoring Stack
################################################################################

resource "helm_release" "kube_prometheus_stack" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.1.3"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  set {
    name  = "grafana.adminPassword"
    value = "Gr4fana!ChangeMeNow"
  }

  set {
    name  = "grafana.ingress.enabled"
    value = "true"
  }

  set {
    name  = "grafana.ingress.ingressClassName"
    value = "alb"
  }

  set {
    name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme"
    value = "internet-facing"
  }

  set {
    name  = "grafana.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type"
    value = "ip"
  }

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "15d"
  }

  depends_on = [module.addons]
}
