# ---------------------------------------------------------------------------
# modules/addons/main.tf
# Cluster add-ons deployed via Helm:
#   - AWS Load Balancer Controller (ALB Ingress)
#   - External Secrets Operator
#   - KEDA (Kubernetes Event-Driven Autoscaling)
#   - Cluster Autoscaler
#   - ECR repositories for both services
# ---------------------------------------------------------------------------

terraform {
  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 5.40" }
    helm       = { source = "hashicorp/helm", version = "~> 2.12" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.27" }
  }
}

locals {
  oidc_host = replace(var.oidc_provider_url, "https://", "")
}

# ---------------------------------------------------------------------------
# ECR Repositories
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "api_service" {
  name                 = var.ecr_api_service_repo
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # Amazon Inspector scans on every push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = var.ecr_api_service_repo }
}

resource "aws_ecr_repository" "worker_service" {
  name                 = var.ecr_worker_service_repo
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = var.ecr_worker_service_repo }
}

resource "aws_ecr_lifecycle_policy" "api_service" {
  repository = aws_ecr_repository.api_service.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["prod-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "worker_service" {
  repository = aws_ecr_repository.worker_service.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["prod-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Remove untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IRSA — AWS Load Balancer Controller
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "alb_controller_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.cluster_name}-alb-controller"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
}

# AWS-provided policy for the LBC — contains all required EC2/ELB permissions
resource "aws_iam_policy" "alb_controller" {
  name = "${var.cluster_name}-alb-controller-policy"

  # Full LBC IAM policy from AWS docs (v2.7.2)
  policy = file("${path.module}/alb-controller-iam-policy.json")
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

# ServiceAccount — Helm chart reads the annotation to discover the role ARN
resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.alb_controller.arn
    }
    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
    }
  }
}

resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.7.2"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.alb_controller.metadata[0].name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "replicaCount"
    value = "2" # HA — one per AZ
  }

  depends_on = [
    kubernetes_service_account.alb_controller,
    aws_iam_role_policy_attachment.alb_controller
  ]
}

# ---------------------------------------------------------------------------
# IRSA — External Secrets Operator
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "external_secrets_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.cluster_name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_assume.json
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "external-secrets-policy"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:${var.cluster_name}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter/${var.cluster_name}/*"
      }
    ]
  })
}

resource "kubernetes_namespace" "external_secrets" {
  metadata { name = "external-secrets" }
}

resource "kubernetes_service_account" "external_secrets" {
  metadata {
    name      = "external-secrets-sa"
    namespace = kubernetes_namespace.external_secrets.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets.arn
    }
  }
}

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.9.14"
  namespace  = kubernetes_namespace.external_secrets.metadata[0].name

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.external_secrets.metadata[0].name
  }

  depends_on = [kubernetes_service_account.external_secrets]
}

# ---------------------------------------------------------------------------
# KEDA — Kubernetes Event-Driven Autoscaling
# Scales the worker service based on SQS queue depth
# ---------------------------------------------------------------------------

resource "kubernetes_namespace" "keda" {
  metadata { name = "keda" }
}

data "aws_iam_policy_document" "keda_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:keda:keda-operator"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
  }
}

resource "aws_iam_role" "keda" {
  name               = "${var.cluster_name}-keda"
  assume_role_policy = data.aws_iam_policy_document.keda_assume.json
}

resource "aws_iam_role_policy" "keda" {
  name = "keda-sqs-policy"
  role = aws_iam_role.keda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
      Resource = "*"
    }]
  })
}

resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = "2.14.0"
  namespace  = kubernetes_namespace.keda.metadata[0].name

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.keda.arn
  }

  set {
    name  = "podIdentity.provider"
    value = "aws"
  }
}

# ---------------------------------------------------------------------------
# Cluster Autoscaler
# ---------------------------------------------------------------------------

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  version    = "9.36.0"
  namespace  = "kube-system"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.cluster_autoscaler_role_arn
  }

  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }
}
