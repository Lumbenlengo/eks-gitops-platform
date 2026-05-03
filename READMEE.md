# LT-Lumbe-Tech — EKS GitOps Platform

A production-grade, cloud-native event processing platform built on AWS EKS.
Demonstrates microservices architecture, GitOps delivery, event-driven autoscaling,
and full observability — the stack used in financial and healthcare systems.

```
POST /items → API Service → SQS → Worker Service → DynamoDB
                 ↓                      ↓
           Prometheus              CloudWatch
                 ↓                      ↓
             Grafana               KEDA (0→N pods)
```

---

## Architecture

| Layer | Technology | Why |
|---|---|---|
| Compute | AWS EKS 1.29 (managed node groups) | Production-grade Kubernetes without control plane overhead |
| GitOps | ArgoCD | Git is the single source of truth — no manual kubectl |
| Autoscaling | KEDA (SQS trigger) + HPA (CPU) | Worker scales to zero when queue is empty — zero idle cost |
| Secrets | AWS Secrets Manager + External Secrets Operator | No secrets in Git, ever |
| Auth | IRSA + GitHub OIDC | Zero long-lived credentials anywhere in the system |
| Observability | Prometheus + Grafana + CloudWatch | Metrics, alerting, and dashboards from day one |
| Storage | DynamoDB (items) + SQS (queue) | Serverless, no cluster storage to manage |
| Networking | ALB Ingress Controller, private nodes | Nodes never exposed to the internet |

---

## Services

### api-service (FastAPI)
Receives events via HTTP, persists to DynamoDB, publishes to SQS.

- `GET  /health` — returns hostname and AZ (proves multi-AZ load balancing)
- `GET  /items` — lists items with optional status filter
- `POST /items` — creates item, publishes to SQS for async processing
- `DELETE /items/{id}` — soft-delete (status = deleted)
- `GET  /metrics` — Prometheus scrape endpoint

### worker-service (Python)
Long-running SQS consumer. Processes messages, updates DynamoDB.

- SQS long-polling (20s) — efficient, low-cost
- Graceful SIGTERM handling — finishes current message before shutdown
- 5% simulated failure rate — realistic error budget for SRE practice
- CloudWatch custom metrics — feeds KEDA for autoscaling decisions
- Scales from **0 to 20 replicas** based on queue depth

---

## Project Structure

```
.
├── app/
│   ├── api-service/          # FastAPI — HTTP ingestion layer
│   └── worker-service/       # Python — SQS consumer + processor
├── helm-charts/
│   ├── api-service/          # HPA: 2→10 pods by CPU
│   └── worker-service/       # KEDA: 0→20 pods by SQS depth
├── argocd/
│   ├── projects/             # ArgoCD Project (RBAC boundary)
│   └── apps/                 # ArgoCD Applications (api + worker)
├── terraform/
│   ├── main.tf               # Root module — ArgoCD, Prometheus, namespaces
│   ├── modules/
│   │   ├── networking/       # VPC, subnets, NAT Gateway (3 AZs)
│   │   ├── eks/              # Cluster, node groups, OIDC, KMS, add-ons
│   │   ├── irsa/             # IAM roles for api-service and worker-service
│   │   └── addons/           # ALB controller, KEDA, External Secrets, Cluster Autoscaler
│   └── github-actions-iam.tf # OIDC provider + CI/CD IAM role
├── grafana-dashboards/
│   └── platform-overview.json # Pre-built dashboard — import directly into Grafana
├── docs/adr/                 # Architecture Decision Records
└── bootstrap.sh              # One-command cluster provisioning
```

---

## Quickstart

### Prerequisites
- AWS CLI configured with admin permissions
- Terraform >= 1.7
- kubectl, helm

### 1. Configure variables
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars — fill in account_id, passwords, etc.
```

### 2. Bootstrap the cluster
```bash
chmod +x bootstrap.sh
./bootstrap.sh
```
This provisions VPC → EKS → IRSA → Addons → ArgoCD → Prometheus in the correct order (~25 minutes total).

### 3. Deploy applications via ArgoCD
```bash
# Update ArgoCD app parameters with terraform outputs
terraform -chdir=terraform output  # Copy ECR URLs and role ARNs

# Apply ArgoCD applications — ArgoCD takes it from here
kubectl apply -f argocd/projects/
kubectl apply -f argocd/apps/
```

### 4. Configure GitHub Secrets
In your GitHub repository → Settings → Secrets:

| Secret | Value |
|---|---|
| `ECR_API_REPO` | `terraform output ecr_api_service_url` |
| `ECR_WORKER_REPO` | `terraform output ecr_worker_service_url` |
| `AWS_ROLE_ARN` | `terraform output github_actions_role_arn` |

### 5. Import Grafana dashboard
In Grafana → Dashboards → Import → upload `grafana-dashboards/platform-overview.json`

---

## GitOps flow

```
git push → GitHub Actions → docker build → ECR push
                          → update image.tag in values.yaml
                          → git commit [skip ci]
                          → ArgoCD detects diff → kubectl apply
```

Every production change is a Git commit. No manual kubectl in production.

---

## KEDA autoscaling

The worker-service scales based on SQS queue depth:

| Queue depth | Worker replicas |
|---|---|
| 0 | 0 (scale to zero — zero cost) |
| 1–5 | 1 |
| 6–50 | 2–10 |
| 51–100 | 11–20 |

Scale-up is aggressive (5 pods per 15s). Scale-down is conservative (2 pods per 30s, 60s cooldown) to avoid thrashing.

---

## Architecture Decision Records

- [ADR 001](docs/adr/001-gitops-over-imperative.md) — GitOps over imperative kubectl
- [ADR 002](docs/adr/002-irsa-over-node-role.md) — IRSA over node-level IAM roles
- [ADR 003](docs/adr/003-keda-over-hpa-worker.md) — KEDA over HPA for worker autoscaling
- [ADR 004](docs/adr/004-oidc-over-static-credentials.md) — GitHub OIDC over static IAM credentials

---

## Cost estimate

| Resource | Cost |
|---|---|
| EKS control plane | ~$0.10/hr |
| 2× t3.medium nodes | ~$0.094/hr |
| ALB | ~$0.008/hr + LCU |
| SQS + DynamoDB | ~$0.00 (free tier) |
| **Total (cluster running)** | **~$8–10/day** |

**Cost-saving tip:** Destroy the cluster when not in use. All state is in Terraform and Git.
```bash
terraform -chdir=terraform destroy
# Recreate in ~20 minutes when needed
```

---

*Built by Patrício Lumbe — [Lumbenlengo.com](https://Lumbenlengo.com)*