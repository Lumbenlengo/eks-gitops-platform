# ADR 001 — GitOps over Imperative Deployments

**Status:** Accepted  
**Date:** 2025-01-01  
**Author:** Patricio Lumbe  
**Deciders:** Platform Team

---

## Context

We needed a deployment strategy for two services (api-service, worker-service) running on EKS.
The two primary options were:

- **Option A — Imperative**: CI pipeline runs `kubectl apply` or `helm upgrade` directly, using a
  kubeconfig stored as a GitHub Secret.
- **Option B — GitOps (ArgoCD)**: CI pipeline updates a Helm values file in Git. ArgoCD watches
  the Git repository and reconciles the cluster state to match.

## Decision

We chose **Option B — GitOps with ArgoCD**.

## Rationale

### 1. Git is the single source of truth

With imperative deployments, the cluster state can drift from what is in the repository. A
developer could run `kubectl edit deployment` in the cluster and the change would never be
recorded. With ArgoCD, any manual cluster change is immediately detected as drift and can be
automatically reverted. What is in Git IS what is in production.

### 2. No kubeconfig stored in CI

The imperative approach requires storing a kubeconfig or service account token with cluster-admin
privileges in GitHub Secrets. This is a significant attack surface: a compromised GitHub secret
means cluster compromise. With ArgoCD, the CI pipeline only pushes a file to Git. ArgoCD, running
inside the cluster, pulls from Git and applies changes. The CI system never touches the cluster
directly.

### 3. Automatic rollback on health failure

ArgoCD monitors pod health via readiness probes. If a new deployment fails health checks, ArgoCD
can be configured to automatically roll back to the previous revision. This happens without human
intervention and without the CI pipeline needing error-handling logic for cluster failures.

### 4. Full audit trail

Every deployment is a Git commit with author, timestamp, and diff. The ArgoCD UI shows the full
sync history. Combined, these give a complete audit trail: who deployed what, when, and what
changed. This is required for SOC 2 Type II and ISO 27001 compliance.

### 5. Separation of CI and CD concerns

CI (build, test, push) and CD (deploy) are separate systems with separate permissions. A developer
who can trigger a build cannot directly deploy to production — they can only update a values file,
which ArgoCD then applies after its own health and sync checks.

## Consequences

- ArgoCD must be bootstrapped into the cluster by Terraform (one-time operation).
- The CI pipeline must have write access to the Git repository to update Helm values.
- Developers need to learn the ArgoCD UI/CLI to observe deployments (low learning curve).
- Rollbacks are a `git revert` — familiar to all engineers.

## Rejected alternative

**Flux CD** was considered. Flux is equally valid and is the other CNCF-graduated GitOps engine.
We chose ArgoCD because of its superior UI for visualising application state, its AppProject RBAC
model, and broader industry adoption at the time of this decision.

---

*Next ADR: [002 — IRSA over Node-Level IAM Roles](002-irsa-over-node-role.md)*
