# eks-gitops-platform

**Production-grade EKS cluster with ArgoCD GitOps, KEDA event-driven autoscaling, IRSA, External Secrets, Prometheus/Grafana, and full Terraform IaC.**

Live endpoint: **`https://api.patriciolumbe.com/health`** — call it repeatedly to observe Multi-AZ load balancing in action.

```bash
# Watch the availability_zone field rotate across us-east-1a, 1b, 1c
for i in $(seq 1 10); do curl -s https://api.patriciolumbe.com/health | python3 -m json.tool; done
```

---

## What this is

A complete, original EKS platform built from scratch with Terraform — not a tutorial clone. It simulates what a Series B startup would run in production in 2025: GitOps deployments, event-driven worker scaling, zero-static-key authentication, and full observability.

**Two services. One cluster. Zero static credentials.**

| Service | Role | Scales via |
|---|---|---|
| **api-service** | FastAPI: `/health`, `/items` CRUD, publishes to SQS | HPA on CPU (2→10 pods) |
| **worker-service** | SQS consumer → DynamoDB writer | KEDA on queue depth (0→20 pods) |

The worker service scales to **zero pods when the queue is empty** — zero idle cost, zero wasted compute. When messages arrive, KEDA scales it up within 15 seconds.

---

## Architecture

```
                         ┌─────────────────────────────────────────────┐
                         │              AWS Account                     │
                         │                                              │
  GitHub ─────OIDC──────▶│  github-actions-terraform role               │
  Actions ────OIDC──────▶│  github-actions-eks-gitops role              │
                         │                                              │
                         │  ┌──────────────────────────────────────┐   │
                         │  │             VPC (10.0.0.0/16)         │   │
                         │  │                                      │   │
  Internet               │  │  ┌──────────┐    ┌──────────────┐   │   │
    │                    │  │  │ Public   │    │ Private       │   │   │
    ▼                    │  │  │ Subnets  │    │ Subnets       │   │   │
  Route53 ─────────────▶│  │  │ (3 AZs)  │    │ (3 AZs)       │   │   │
  api.patriciolumbe.com  │  │  │          │    │               │   │   │
    │                    │  │  │  ALB     │    │  EKS Nodes    │   │   │
    ▼                    │  │  │  (HTTPS) │───▶│  (t3.medium)  │   │   │
  ACM Certificate        │  │  │          │    │  ASG 2→10     │   │   │
                         │  │  │  NAT GW  │    │               │   │   │
                         │  │  │  (3 AZs) │    │  api-service  │   │   │
                         │  │  └──────────┘    │  (HPA)        │   │   │
                         │  │                  │               │   │   │
                         │  │                  │  worker-svc   │   │   │
                         │  │                  │  (KEDA→0)     │   │   │
                         │  │                  └──────────────┘   │   │
                         │  └──────────────────────────────────────┘   │
                         │                                              │
                         │  SQS Queue ◀── api-service                  │
                         │       │                                      │
                         │       └──▶ worker-service ──▶ DynamoDB       │
                         │                                              │
                         │  ECR (api-service image)                     │
                         │  ECR (worker-service image)                  │
                         │  Secrets Manager (app secrets)               │
                         │  CloudWatch (metrics + logs + alarms)        │
                         └─────────────────────────────────────────────┘

  GitOps flow:
  GitHub push ──▶ CI builds image + updates Helm values.yaml ──▶ ArgoCD detects diff
       ──▶ ArgoCD applies Helm release ──▶ Rolling update ──▶ Health check ──▶ Done
```

---

## Services table

| Layer | Service | Configuration | Terraform module |
|---|---|---|---|
| DNS | Route53 | Hosted zone, alias to ALB | `networking/` |
| SSL | ACM | api.patriciolumbe.com, auto-renew | `addons/` |
| Load balancing | AWS ALB | HTTPS 443, managed by ALB Ingress Controller | `addons/` |
| Cluster | EKS 1.29 | Private nodes, public API endpoint, KMS secrets encryption | `eks/` |
| Nodes | EC2 ASG | t3.medium, min=2 max=10, IMDSv2, encrypted EBS | `eks/` |
| Autoscaling | Cluster Autoscaler | Scales node group based on pending pods | `addons/` |
| GitOps | ArgoCD 6.7.3 | Watches Git, auto-syncs, self-heals | `main.tf` |
| App scaling | HPA | api-service: CPU 70% → 2→10 pods | Helm chart |
| Queue scaling | KEDA | worker-service: SQS depth → 0→20 pods | Helm chart |
| Secrets sync | External Secrets | AWS Secrets Manager → Kubernetes Secrets | `addons/` |
| Auth (pods) | IRSA | Per-service IAM roles, OIDC trust, zero static keys | `irsa/` |
| Auth (CI) | GitHub OIDC | Plan + apply with no stored AWS credentials | `eks/` |
| Queue | SQS + DLQ | KMS-encrypted, 3-retry DLQ, queue policy per role | `irsa/` |
| Database | DynamoDB | PAY_PER_REQUEST, PITR, GSI on status, KMS | `irsa/` |
| Images | ECR x2 | Scan on push, lifecycle policy (keep last 10) | `addons/` |
| Monitoring | Prometheus + Grafana | kube-prometheus-stack, ServiceMonitor per service | `main.tf` |
| Network | VPC Flow Logs | All traffic logged to CloudWatch, 30-day retention | `networking/` |
| IaC state | S3 + DynamoDB | Versioned, encrypted, lock table | `backend.tf` |

---

## GitOps deployment flow

```
Step 1 — Developer pushes code to feature branch
         └─▶ CI: runs tests (pytest, coverage > 80%)

Step 2 — PR opened against main
         └─▶ Terraform: plan runs, output posted as PR comment
         └─▶ Code review required before merge

Step 3 — PR merged to main
         └─▶ CI: docker build → push to ECR (tagged prod-<sha>-<run>)
         └─▶ CI: trivy scan (fail on CRITICAL CVEs)
         └─▶ CI: update helm-charts/*/values.yaml image.tag
         └─▶ CI: git commit "chore(gitops): update image tags [skip ci]"
         └─▶ CI: git push to main

Step 4 — ArgoCD detects values.yaml diff (polls Git every 3 min)
         └─▶ ArgoCD: helm template → kubectl apply (server-side)
         └─▶ ArgoCD: monitors pod readiness probes
         └─▶ ArgoCD: marks sync as Healthy or triggers rollback

Step 5 — Zero-downtime rolling update
         └─▶ maxSurge=1, maxUnavailable=0
         └─▶ PDB ensures ≥1 pod available during update
         └─▶ ALB only routes to Ready pods (readiness probe must pass)
```

**No human runs `kubectl`. The Git repository IS the source of truth.**

---

## IRSA — how pods authenticate to AWS

Every pod that calls an AWS API uses IRSA. Zero static credentials. Zero IAM users.

```
Pod starts
  │
  ▼
Kubernetes projects OIDC token into pod filesystem
(/var/run/secrets/eks.amazonaws.com/serviceaccount/token)
  │
  ▼
AWS SDK reads token automatically (AWS_WEB_IDENTITY_TOKEN_FILE env var)
  │
  ▼
SDK calls STS AssumeRoleWithWebIdentity
  │
  ▼
STS validates: token signature + sub claim matches trust policy
  ("system:serviceaccount:api-service:api-service" ✓)
  │
  ▼
STS issues temporary credentials (valid 15 minutes, auto-refreshed)
  │
  ▼
Pod calls DynamoDB / SQS / Secrets Manager with scoped permissions
```

The trust policy ensures only the correct service account in the correct namespace can assume
each role — enforced by AWS STS, not just Kubernetes RBAC.

---

## KEDA — worker scales to zero

```
Queue empty (0 messages):
  KEDA ScaledObject → sets Deployment replicas = 0
  Zero pods running. Zero cost.

10 messages arrive:
  KEDA polls SQS every 15 seconds
  sqsQueueLength=5 → ceil(10/5) = 2 replicas
  Deployment scales to 2 pods within ~20 seconds

500 messages arrive:
  ceil(500/5) = 100 → capped at maxReplicaCount=20
  Cluster Autoscaler adds nodes if needed
  All 500 messages processed in parallel

Queue drains:
  cooldownPeriod=60s → KEDA waits 60s of empty queue before scaling to 0
  Worker-service → 0 pods
```

---

## Cost estimate

| Resource | Configuration | Monthly cost |
|---|---|---|
| EKS control plane | 1 cluster | $73.00 |
| EC2 nodes | 2× t3.medium (min) | $60.74 |
| ALB | 1 load balancer | ~$20.00 |
| NAT Gateways | 3× (one per AZ) | ~$99.00 |
| ECR | 2 repos, ~1GB | ~$0.10 |
| SQS | Under free tier | $0.00 |
| DynamoDB | PAY_PER_REQUEST, low traffic | ~$1.00 |
| CloudWatch | Logs + metrics | ~$5.00 |
| **Total (min load)** | | **~$258/month** |

> **Reduce cost for dev/testing**: Use 1 NAT Gateway instead of 3 (`nat_gateway_count = 1`). Saves ~$66/month. Accept that an AZ failure blocks private subnet egress.

---

## Local setup

### Prerequisites

```bash
# Required tools
aws --version          # >= 2.15
terraform --version    # >= 1.7
kubectl version        # >= 1.29
helm version           # >= 3.14
argocd version         # >= 2.10
```

### Bootstrap state backend (one-time)

```bash
# Create S3 bucket and DynamoDB table for Terraform state
aws s3api create-bucket \
  --bucket patriciolumbe-terraform-state \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket patriciolumbe-terraform-state \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket patriciolumbe-terraform-state \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

### Deploy infrastructure

```bash
cd terraform

# Initialise Terraform with remote state backend
terraform init

# Review what will be created (~35 resources)
terraform plan -out=tfplan

# Apply — takes ~15 minutes (EKS cluster creation dominates)
terraform apply tfplan

# Configure kubectl
$(terraform output -raw configure_kubectl)

# Verify nodes are ready
kubectl get nodes -o wide
```

### Bootstrap ArgoCD applications

```bash
# ArgoCD is already installed by Terraform
# Get the initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port-forward to ArgoCD UI (or use the ALB ingress URL)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Open https://localhost:8080 — login with admin + password above

# Apply the AppProject first, then the Applications
kubectl apply -f argocd/projects/eks-gitops-platform.yaml
kubectl apply -f argocd/apps/api-service.yaml
kubectl apply -f argocd/apps/worker-service.yaml

# Watch ArgoCD sync the applications
argocd app list
argocd app get api-service
```

### Verify the full GitOps loop

```bash
# 1. Make a trivial change to the API service
echo "# change" >> app/api-service/main.py
git add . && git commit -m "test: trigger GitOps loop"
git push origin main

# 2. Watch CI pipeline run in GitHub Actions
# 3. Watch ArgoCD detect the Helm values.yaml change
argocd app get api-service --watch

# 4. Watch the rolling update
kubectl rollout status deployment/api-service -n api-service

# 5. Confirm the new version is live
curl https://api.patriciolumbe.com/health | python3 -m json.tool
```

### Test KEDA worker scaling

```bash
# Send 50 messages to SQS to trigger scaling
SQS_URL=$(terraform -chdir=terraform output -raw sqs_queue_url)

for i in $(seq 1 50); do
  aws sqs send-message \
    --queue-url "$SQS_URL" \
    --message-body "{\"item_id\":\"test-$i\",\"name\":\"Test Item $i\",\"priority\":5,\"created_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"action\":\"process_item\"}"
done

# Watch KEDA scale the worker service
kubectl get pods -n worker-service -w

# Check ScaledObject status
kubectl describe scaledobject worker-service -n worker-service
```

---

## Architecture Decision Records

| ADR | Decision | Why it matters |
|---|---|---|
| [001](docs/adr/001-gitops-over-imperative.md) | GitOps (ArgoCD) over imperative kubectl | No kubeconfig in CI, full audit trail, self-healing |
| [002](docs/adr/002-irsa-over-node-role.md) | IRSA over node IAM roles | Per-pod least privilege, no static credentials |
| [003](docs/adr/003-keda-over-hpa-worker.md) | KEDA over HPA for worker | Scale to zero, queue-depth-aware scaling |

---

## Interview one-liners

> *"This cluster has no static AWS credentials anywhere — not in CI, not in pods, not in Secrets Manager. GitHub Actions uses OIDC to assume a role. Pods use IRSA via the cluster's OIDC provider. The trust policies are namespace-scoped at the AWS STS level."*

> *"The worker service costs zero when idle. KEDA reads the SQS queue depth every 15 seconds and sets the Deployment replica count proportionally. When the queue empties, it scales to zero pods. The cluster autoscaler then removes the idle node."*

> *"No developer runs kubectl to deploy. They push code. CI builds the image, updates a values.yaml line, and pushes that commit to Git. ArgoCD detects the diff in the Helm chart and applies the new release. Git is the source of truth."*

---

**patriciolumbe.com** · [LinkedIn](https://linkedin.com/in/patriciolumbe) · [Malt](https://malt.fr/profile/patriciolumbe)
