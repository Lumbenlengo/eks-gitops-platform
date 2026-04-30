# ---------------------------------------------------------------------------
# modules/irsa/main.tf
# IRSA = IAM Roles for Service Accounts
#
# This module creates per-service IAM roles that pods can assume via
# Kubernetes service accounts. The OIDC trust policy ensures ONLY pods in
# the correct namespace and with the correct service account name can assume
# the role — no static credentials, no node-wide IAM permissions.
#
# It also creates the AWS resources the services need:
#   - SQS queue (with DLQ) consumed by the worker service
#   - DynamoDB table written to by the worker service
#   - KMS key for SQS message encryption
# ---------------------------------------------------------------------------

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.40" }
  }
}

locals {
  oidc_host = replace(var.oidc_provider_url, "https://", "")
}

# ---------------------------------------------------------------------------
# KMS key for SQS encryption
# ---------------------------------------------------------------------------

resource "aws_kms_key" "sqs" {
  description             = "KMS key for SQS queue encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_kms_alias" "sqs" {
  name          = "alias/${var.cluster_name}-sqs"
  target_key_id = aws_kms_key.sqs.key_id
}

# ---------------------------------------------------------------------------
# SQS — Dead Letter Queue
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.sqs_queue_name}-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = aws_kms_key.sqs.arn

  tags = { Name = "${var.sqs_queue_name}-dlq" }
}

# ---------------------------------------------------------------------------
# SQS — Main Queue
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "main" {
  name                       = var.sqs_queue_name
  visibility_timeout_seconds = 300 # Must be >= Lambda/worker timeout
  message_retention_seconds  = 86400
  kms_master_key_id          = aws_kms_key.sqs.arn

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = var.sqs_queue_name }
}

resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowWorkerServiceOnly"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.worker_service.arn
        }
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.main.arn
      },
      {
        Sid    = "AllowApiServicePublish"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.api_service.arn
        }
        Action   = ["sqs:SendMessage", "sqs:GetQueueUrl"]
        Resource = aws_sqs_queue.main.arn
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# DynamoDB — Items table
# ---------------------------------------------------------------------------

resource "aws_dynamodb_table" "items" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  range_key    = "created_at"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "StatusIndex"
    hash_key        = "status"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = true
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = { Name = var.dynamodb_table_name }
}

# ---------------------------------------------------------------------------
# IRSA — API Service Role
# Trust policy: only the api-service ServiceAccount in api-service namespace
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "api_service_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:api-service:api-service"]
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

resource "aws_iam_role" "api_service" {
  name               = "${var.cluster_name}-api-service"
  assume_role_policy = data.aws_iam_policy_document.api_service_assume.json

  tags = { Name = "${var.cluster_name}-api-service-irsa" }
}

resource "aws_iam_role_policy" "api_service" {
  name = "api-service-policy"
  role = aws_iam_role.api_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSSendMessage"
        Effect = "Allow"
        Action = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.main.arn
      },
      {
        Sid    = "DynamoDBReadWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.items.arn,
          "${aws_dynamodb_table.items.arn}/index/*"
        ]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.sqs.arn
      },
      {
        Sid    = "SSMGetParameters"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:${var.aws_region}:${var.account_id}:parameter/${var.cluster_name}/api-service/*"
      },
      {
        Sid    = "SecretsManagerRead"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:${var.cluster_name}/api-service/*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IRSA — Worker Service Role
# Trust policy: only the worker-service ServiceAccount in worker-service ns
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "worker_service_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:worker-service:worker-service"]
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

resource "aws_iam_role" "worker_service" {
  name               = "${var.cluster_name}-worker-service"
  assume_role_policy = data.aws_iam_policy_document.worker_service_assume.json

  tags = { Name = "${var.cluster_name}-worker-service-irsa" }
}

resource "aws_iam_role_policy" "worker_service" {
  name = "worker-service-policy"
  role = aws_iam_role.worker_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSConsumeMessages"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [aws_sqs_queue.main.arn, aws_sqs_queue.dlq.arn]
      },
      {
        Sid    = "DynamoDBWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.items.arn,
          "${aws_dynamodb_table.items.arn}/index/*"
        ]
      },
      {
        Sid    = "KMSDecrypt"
        Effect = "Allow"
        Action = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource = aws_kms_key.sqs.arn
      },
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "EKSGitOpsPlatform/WorkerService"
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IRSA — Cluster Autoscaler Role
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cluster_autoscaler_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
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

resource "aws_iam_role" "cluster_autoscaler" {
  name               = "${var.cluster_name}-cluster-autoscaler"
  assume_role_policy = data.aws_iam_policy_document.cluster_autoscaler_assume.json
}

resource "aws_iam_role_policy" "cluster_autoscaler" {
  name = "cluster-autoscaler"
  role = aws_iam_role.cluster_autoscaler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "ec2:DescribeImages",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeLaunchTemplateVersions",
        "ec2:GetInstanceTypesFromInstanceRequirements",
        "eks:DescribeNodegroup"
      ]
      Resource = ["*"]
    }, {
      Effect = "Allow"
      Action = [
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ]
      Resource = ["*"]
      Condition = {
        StringEquals = {
          "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/enabled" : "true"
          "autoscaling:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" : "owned"
        }
      }
    }]
  })
}
