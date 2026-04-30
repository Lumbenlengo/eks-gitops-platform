# ---------------------------------------------------------------------------
# github-actions-iam.tf
#
# Creates the IAM roles that GitHub Actions assumes via OIDC.
# Two roles:
#   1. github-actions-terraform  — plan + apply (broad permissions)
#   2. github-actions-eks-gitops — ECR push only (narrow, for CI builds)
#
# Apply this file ONCE before running the main Terraform — it's a bootstrap
# dependency. You can apply it manually or include it in a separate
# "bootstrap" workspace.
#
# NOTE: This file lives in the root of the repo (not in terraform/) so you
# can apply it independently with:
#   terraform -chdir=bootstrap apply
# ---------------------------------------------------------------------------


variable "github_org" { default = "patriciolumbe" }
variable "github_repo" { default = "eks-gitops-platform" }

# ---------------------------------------------------------------------------
# GitHub OIDC provider (register once per account)
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# ---------------------------------------------------------------------------
# Role 1 — Terraform plan + apply
# Scope: only the specific repo, any branch (plan on PRs, apply on main)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "terraform_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_terraform" {
  name                 = "github-actions-terraform"
  assume_role_policy   = data.aws_iam_policy_document.terraform_assume.json
  max_session_duration = 3600
}

# For a real production account, replace AdministratorAccess with a
# scoped policy that allows only the resources Terraform manages.
resource "aws_iam_role_policy_attachment" "github_terraform_admin" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ---------------------------------------------------------------------------
# Role 2 — ECR push (CI build pipeline)
# Scope: only pushes from main branch (apply branch restriction)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecr_push_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "github_ecr_push" {
  name                 = "github-actions-eks-gitops"
  assume_role_policy   = data.aws_iam_policy_document.ecr_push_assume.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy" "github_ecr_push" {
  name = "ecr-push-policy"
  role = aws_iam_role.github_ecr_push.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ECRAuth"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "ECRPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:DescribeImages",
          "ecr:DescribeRepositories",
          "ecr:BatchGetImage"
        ]
        Resource = [
          "arn:aws:ecr:us-east-1:*:repository/eks-gitops/*"
        ]
      }
    ]
  })
}

output "terraform_role_arn" { value = aws_iam_role.github_terraform.arn }
output "ecr_push_role_arn" { value = aws_iam_role.github_ecr_push.arn }
