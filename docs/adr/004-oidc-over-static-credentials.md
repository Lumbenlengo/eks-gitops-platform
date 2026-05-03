# ADR 004 — GitHub Actions OIDC over static IAM credentials

**Status:** Accepted  
**Date:** 2024-01-01  
**Deciders:** Patrício Lumbe

---

## Context

The CI/CD pipeline needs AWS permissions to push Docker images to ECR and
read Terraform outputs. The naive approach is to create an IAM user, generate
access keys, and store them as GitHub Secrets. This is the most common pattern
but it has serious security implications:

- Long-lived credentials that never expire
- Credentials stored in GitHub's secret store (another attack surface)
- Keys must be manually rotated
- Any secret leak = full AWS access until detected and rotated

## Decision

Use GitHub Actions OIDC (OpenID Connect) to authenticate to AWS without
storing any long-lived credentials.

GitHub Actions can exchange a short-lived OIDC token (valid for the duration
of the job) for temporary AWS credentials via `sts:AssumeRoleWithWebIdentity`.
The IAM role trust policy restricts which repository and branch can assume it.

The Terraform module `github-actions-iam.tf` already provisions:
- An IAM OIDC provider for `token.actions.githubusercontent.com`
- An IAM role with trust policy scoped to `repo:Lumbenlengo/eks-gitops-platform:ref:refs/heads/main`
- Permissions: `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`,
  `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`,
  `ecr:CompleteLayerUpload`

## Consequences

**Positive:**
- Zero long-lived credentials in GitHub Secrets
- Credentials are scoped to the job duration (~15 minutes)
- Trust policy limits blast radius to the main branch only
- Fully auditable via CloudTrail (every assume-role logged)
- No manual key rotation required

**Negative:**
- Slightly more complex setup (OIDC provider must exist before first run)
- GitHub outage = CI outage (same as before, not a new risk)

## Alternatives considered

**IAM User with access keys:** Rejected — long-lived credentials, rotation burden,
secret leak risk.

**EC2 instance profile on a self-hosted runner:** Rejected — operational overhead
of managing a runner instance, and the runner itself becomes a privileged target.