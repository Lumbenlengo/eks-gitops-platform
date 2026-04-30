# ADR 002 — IRSA over Node-Level IAM Roles

**Status:** Accepted  
**Date:** 2025-01-01  
**Author:** Patricio Lumbe  
**Deciders:** Platform Team

---

## Context

Our services (api-service, worker-service) need to call AWS APIs:

- api-service: SQS SendMessage, DynamoDB read/write, Secrets Manager read
- worker-service: SQS ReceiveMessage/DeleteMessage, DynamoDB write, CloudWatch PutMetricData

We needed to decide how pods authenticate to AWS. The options were:

- **Option A — Static credentials**: Store `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in
  Kubernetes Secrets and inject them as environment variables.
- **Option B — Node IAM Role**: Attach a broad IAM role to the EC2 node group. All pods on the
  node inherit the permissions via the instance metadata service.
- **Option C — IRSA**: Create a per-service IAM role with a trust policy that uses the cluster's
  OIDC provider. Pods assume the role via a projected service account token.

## Decision

We chose **Option C — IRSA (IAM Roles for Service Accounts)**.

## Rationale

### 1. Principle of least privilege — per pod, not per node

With a node IAM role, every pod on the node inherits all the node's permissions. If api-service
can access DynamoDB, so can any other pod scheduled on the same node — including a compromised
third-party container. IRSA scopes permissions to the exact service account, in the exact
namespace. The worker-service cannot call SQS SendMessage even if it wanted to — it is not in its
role policy.

### 2. No credentials to rotate or leak

Static credentials in Kubernetes Secrets are base64-encoded, not encrypted by default (unless
KMS encryption is enabled on the cluster, which we do). They appear in `kubectl describe secret`,
in CI logs if accidentally printed, and in any system that reads the secret. IRSA tokens are
short-lived JWT tokens (valid for 15 minutes by default) issued by the Kubernetes API server and
exchanged for temporary STS credentials by the AWS SDK. There is nothing to rotate or leak.

### 3. The trust policy is a hard security boundary

The IRSA trust policy for api-service reads:

```json
{
  "Condition": {
    "StringEquals": {
      "oidc.eks.us-east-1.amazonaws.com/id/XXXX:sub": "system:serviceaccount:api-service:api-service",
      "oidc.eks.us-east-1.amazonaws.com/id/XXXX:aud": "sts.amazonaws.com"
    }
  }
}
```

Only a pod with service account `api-service` in namespace `api-service` can assume this role.
A pod in a different namespace with the same service account name cannot — the namespace is part
of the `sub` claim. This is enforced by AWS STS, not by Kubernetes RBAC, which means it holds
even if Kubernetes RBAC is misconfigured.

### 4. Audit trail via CloudTrail

Every `AssumeRoleWithWebIdentity` call is logged in CloudTrail with the full OIDC subject claim,
which includes the pod's service account and namespace. You can trace every AWS API call to the
exact pod that made it. With static credentials or node roles, you only see the node IP.

## How IRSA works (for interview explanation)

1. The EKS cluster has an OIDC issuer URL (e.g., `https://oidc.eks.us-east-1.amazonaws.com/id/XXXX`).
2. Terraform registers this URL as an OIDC provider in IAM.
3. For each service, Terraform creates an IAM role with a trust policy that allows
   `sts:AssumeRoleWithWebIdentity` from that OIDC provider, conditioned on the specific
   service account subject.
4. The Kubernetes service account is annotated with `eks.amazonaws.com/role-arn`.
5. The EKS Pod Identity webhook (built into EKS) injects a projected volume containing a
   short-lived OIDC token into every pod using that service account.
6. The AWS SDK automatically detects the token file path (via `AWS_WEB_IDENTITY_TOKEN_FILE`
   env var, also injected by the webhook) and exchanges it for STS credentials.
7. The pod has AWS access. No static keys. No rotation. No leakage surface.

## Rejected alternatives

**Option A (static credentials)** was rejected because of credential management overhead and
leakage risk. Rotating secrets across environments is error-prone and creates operational
toil.

**Option B (node role)** was rejected because it violates least privilege — all pods on the node
share the same permissions, which creates excessive blast radius on pod compromise.

---

*Previous ADR: [001 — GitOps over Imperative Deployments](001-gitops-over-imperative.md)*
