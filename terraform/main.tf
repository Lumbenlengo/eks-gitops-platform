terraform {
  required_version = ">= 1.7"

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
}


# Providers


provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.tags
  }
}

# The kubernetes, helm, and kubectl providers all auth via the EKS cluster
# credentials. Using `data` sources here means Terraform fetches a short-lived
# token on every run — no static kubeconfig required.
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }

# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------

module "networking" {
  source = "./modules/networking"

  cluster_name    = var.cluster_name
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "eks" {
  source = "./modules/eks"

  cluster_name       = var.cluster_name
  cluster_version    = var.cluster_version
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids

  node_group_instance_types = var.node_group_instance_types
  node_group_desired_size   = var.node_group_desired_size
  node_group_min_size       = var.node_group_min_size
  node_group_max_size       = var.node_group_max_size

  account_id = data.aws_caller_identity.current.account_id
}

module "irsa" {
  source = "./modules/irsa"

  cluster_name        = var.cluster_name
  oidc_provider_arn   = module.eks.oidc_provider_arn
  oidc_provider_url   = module.eks.cluster_oidc_issuer_url
  sqs_queue_name      = var.sqs_queue_name
  dynamodb_table_name = var.dynamodb_table_name
  account_id          = data.aws_caller_identity.current.account_id
  aws_region          = var.aws_region

  depends_on = [module.eks]
}

module "addons" {
  source = "./modules/addons"

  cluster_name            = var.cluster_name
  cluster_endpoint        = module.eks.cluster_endpoint
  oidc_provider_arn       = module.eks.oidc_provider_arn
  oidc_provider_url       = module.eks.cluster_oidc_issuer_url
  vpc_id                  = module.networking.vpc_id
  aws_region              = var.aws_region
  account_id              = data.aws_caller_identity.current.account_id
  ecr_api_service_repo    = var.ecr_api_service_repo
  ecr_worker_service_repo = var.ecr_worker_service_repo

  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# ArgoCD namespace + Helm install
# ArgoCD is installed via Helm directly from Terraform so that the cluster
# is GitOps-managed from day one. All subsequent app deployments go through
# ArgoCD — Terraform only manages the bootstrapping.
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [module.eks]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.3"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Disable the built-in admin password for production clusters; use SSO or
  # generate a bcrypt hash. For this project we set a strong hashed password.
  set {
    name = "configs.secret.argocdServerAdminPassword"
    # bcrypt hash of "Adm1n!ChangeMeNow" — rotate on first login
    value = "$2a$10$rRyBsGSHK6.uc8fntPwVIuLVHgsAhAX7TcdrqW/9mu9dS5Pf5CMHK"
  }

  set {
    name  = "server.service.type"
    value = "ClusterIP" # Exposed via ALB Ingress — no direct LoadBalancer
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
    name  = "server.ingress.annotations.kubernetes\\.io/ingress\\.class"
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
    name  = "server.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/listen-ports"
    value = "[{\"HTTPS\":443}]"
  }

  set {
    name  = "server.insecure"
    value = "true" # TLS terminated at ALB
  }

  # Enable server-side apply for large manifests
  set {
    name  = "configs.params.server\\.enable\\.gzip"
    value = "true"
  }

  values = [
    yamlencode({
      global = {
        logging = {
          format = "json"
          level  = "info"
        }
      }
      repoServer = {
        resources = {
          requests = { cpu = "100m", memory = "256Mi" }
          limits   = { cpu = "500m", memory = "512Mi" }
        }
      }
      applicationSet = {
        enabled = true
      }
      notifications = {
        enabled = true
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    module.addons # ALB Ingress Controller must be ready first
  ]
}

# ---------------------------------------------------------------------------
# App namespaces — created by Terraform; managed by ArgoCD after bootstrap
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "api_service" {
  metadata {
    name = "api-service"
    labels = {
      "app.kubernetes.io/managed-by" = "argocd"
      environment                    = var.environment
    }
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "worker_service" {
  metadata {
    name = "worker-service"
    labels = {
      "app.kubernetes.io/managed-by" = "argocd"
      environment                    = var.environment
    }
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# Prometheus + Grafana via Helm (kube-prometheus-stack)
# ---------------------------------------------------------------------------

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
    name  = "grafana.service.type"
    value = "ClusterIP"
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
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "15d"
  }

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          resources = {
            requests = { cpu = "200m", memory = "400Mi" }
            limits   = { cpu = "1000m", memory = "2Gi" }
          }
        }
      }
      alertmanager = {
        config = {
          global = {
            resolve_timeout = "5m"
          }
          route = {
            receiver = "slack-notifications"
            routes = [{
              match    = { severity = "critical" }
              receiver = "slack-notifications"
            }]
          }
          receivers = [{
            name = "slack-notifications"
            slack_configs = [{
              api_url       = "https://hooks.slack.com/services/REPLACE_WITH_WEBHOOK"
              channel       = "#alerts"
              title         = "{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}"
              text          = "{{ range .Alerts }}{{ .Annotations.description }}{{ end }}"
              send_resolved = true
            }]
          }]
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.monitoring,
    module.addons
  ]
}
