# eks-gitops-platform

<p>
  <img src="https://img.shields.io/badge/IaC-Terraform-844FBA?logo=terraform&logoColor=white" height="20">
  <img src="https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazonaws&logoColor=white" height="20">
  <img src="https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white" height="20">
</p>

<p>
  <img width="50" height="50" alt="Amazon CloudWatch" src="https://github.com/user-attachments/assets/c43bbdee-c510-4c4b-8189-dfc972d34397" />
  <img width="50" height="50" alt="AWS Secrets Manager" src="https://github.com/user-attachments/assets/07c91d5a-9601-415d-8fd9-cd6522b66ac8" />
  <img width="50" height="50" alt="AWS Identity and Access Management (IAM)" src="https://github.com/user-attachments/assets/05b64da2-347c-4ec3-869d-c43ae6c3a31b" />
  <img width="50" height="50" alt="Amazon DynamoDB" src="https://github.com/user-attachments/assets/df976202-72ee-457b-b58f-9509d8ee2427" />
  <img width="50" height="50" alt="Amazon Route 53" src="https://github.com/user-attachments/assets/fe0d34b0-e237-46ea-942a-9483d7abc4af" />
  <img width="50" height="50" alt="Elastic Load Balancing (ELB)" src="https://github.com/user-attachments/assets/701f7251-1288-4bf5-ad96-8f00b486af7e" />
  <img width="50" height="50" alt="Amazon EC2 Auto Scaling" src="https://github.com/user-attachments/assets/3ec28aa2-857b-4daf-bca4-a7600dd042d9" />
  <img width="50" height="50" alt="Amazon EC2" src="https://github.com/user-attachments/assets/d0917868-b83b-4bbe-b0a2-967e169ed8ea" />
</p>

An Amazon EKS platform built with Terraform, running two services with GitOps delivery through ArgoCD, event driven autoscaling through KEDA, and no static AWS credentials anywhere in the pipeline.

## Why I built this

I wanted to go past the usual "deploy nginx on Kubernetes" tutorial and actually build the pattern that platform teams run in production: infrastructure defined entirely in code, deployments driven by Git instead of by a person typing kubectl, workloads authenticating to AWS through short lived tokens instead of stored keys, and a worker that costs nothing while it has no work to do. This repository is the result of building that out layer by layer, including the design decisions and the tradeoffs I rejected along the way.

## Status

This project is maintained as infrastructure as code rather than a permanently running service. The AWS resources described below (EKS cluster, ALB, NAT gateways, and so on) are provisioned on demand to avoid ongoing cost when I am not actively demoing or extending the project. Everything, Terraform modules, Helm charts, ArgoCD manifests, and CI workflows, is complete and versioned in this repository whether or not the environment is up at the moment you read this.

Screenshots of the running cluster (ArgoCD, Grafana, and the API itself) are in `docs/screenshots/`.

## What runs on it

Two services share the cluster:

| Service | Purpose | Scales via |
|---|---|---|
| api-service | FastAPI app exposing `/health` and `/items`, publishes work to SQS | HPA on CPU, 2 to 10 pods |
| worker-service | Consumes SQS messages, writes to DynamoDB | KEDA on queue depth, 0 to 20 pods |

The part I care most about is the worker. When the queue is empty it runs zero pods, not a padded minimum of one or two kept warm just in case. KEDA checks the queue depth every 15 seconds and adjusts the replica count accordingly, so idle time costs nothing.

There is also a small static demo UI under `app/api-service/static/` (an ops dashboard and a storefront page) so the API has something visual to demo besides curl output.

## Architecture

<p align="center">
  <img src="https://github.com/user-attachments/assets/95b0345f-d961-40c2-adf1-078078bfa72b" alt="Production-Grade Amazon EKS GitOps Platform - Architecture" style="width: 100%; max-width: 1000px; height: auto;" />
</p>

```

## How a deploy happens

1. A feature branch is pushed. CI runs the test suite with a coverage gate of 80 percent.
2. A pull request against `main` triggers a Terraform plan, posted as a PR comment, and requires review before merge.
3. On merge, CI builds the image, pushes it to ECR tagged `prod-<sha>-<run>`, scans it with Trivy (failing the build on CRITICAL CVEs), bumps the tag in `helm-charts/*/values.yaml`, and pushes that commit back to `main`.
4. ArgoCD polls Git every 3 minutes, sees the values.yaml diff, and applies the Helm release server side.
5. The rollout uses `maxSurge=1` and `maxUnavailable=0`, with a PodDisruptionBudget keeping at least one pod available. The ALB only routes to pods that pass their readiness probe.

Nobody runs `kubectl apply` against production. The only path in is a Git commit.

## Security model

Every pod that talks to AWS does it through IRSA rather than a node level IAM role or stored keys. Kubernetes projects a short lived OIDC token into the pod, the AWS SDK exchanges it for temporary STS credentials scoped to that specific service account and namespace, and the credentials refresh automatically every 15 minutes. CI authenticates the same way: GitHub Actions assumes an IAM role through OIDC, so no long lived AWS key is stored as a GitHub secret.

The full reasoning behind this, including the rejected alternatives, is in [ADR 002](docs/adr/002-irsa-over-node-role.md) and [ADR 004](docs/adr/004-oidc-over-static-credentials.md).

## Scaling model

api-service scales on CPU through a standard HPA. worker-service scales on SQS queue depth through KEDA, including down to zero replicas when the queue is empty. CPU is a lagging signal for a queue consumer, it stays low right up until the moment a burst of messages needs processing, so KEDA reading the queue directly reacts sooner and lets the worker cost nothing while idle. The comparison against a plain HPA is written up in [ADR 003](docs/adr/003-keda-over-hpa-worker.md).

## Observability

Prometheus and Grafana run via kube-prometheus-stack, with a ServiceMonitor per service. VPC Flow Logs and application logs go to CloudWatch with a 30 day retention window. A sample dashboard is in `grafana-dashboards/platform-overview.json`.

## What it costs

| Resource | Configuration | Monthly |
|---|---|---|
| EKS control plane | 1 cluster | $73.00 |
| EC2 nodes | 2x t3.medium minimum | $60.74 |
| ALB | 1 | ~$20.00 |
| NAT Gateways | 3, one per AZ | ~$99.00 |
| ECR | 2 repos, ~1GB | ~$0.10 |
| SQS | within free tier | $0.00 |
| DynamoDB | on demand, low traffic | ~$1.00 |
| CloudWatch | logs and metrics | ~$5.00 |
| Total at baseline load | | ~$258/month |

For dev or test, dropping to a single NAT Gateway (`nat_gateway_count = 1`) saves about $66/month. The tradeoff is that an AZ outage takes down private subnet egress for that AZ.

## Running it yourself

Requirements: AWS CLI 2.15+, Terraform 1.7+, kubectl 1.29+, Helm 3.14+, ArgoCD CLI 2.10+.

Bootstrap the Terraform state backend once:

```bash
aws s3api create-bucket \
  --bucket lumbenlengo-terraform-state \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket lumbenlengo-terraform-state \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket lumbenlengo-terraform-state \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

Apply the infrastructure (about 35 resources, roughly 15 minutes, mostly the EKS cluster):

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

$(terraform output -raw configure_kubectl)
kubectl get nodes -o wide
```

Bootstrap ArgoCD (already installed by Terraform):

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

kubectl port-forward svc/argocd-server -n argocd 8080:443
# open https://localhost:8080, log in as admin

kubectl apply -f argocd/projects/eks-gitops-platform.yaml
kubectl apply -f argocd/apps/api-service.yaml
kubectl apply -f argocd/apps/worker-service.yaml

argocd app list
argocd app get api-service
```

Confirm the GitOps loop works end to end:

```bash
echo "# change" >> app/api-service/main.py
git add . && git commit -m "test: trigger GitOps loop"
git push origin main

argocd app get api-service --watch
kubectl rollout status deployment/api-service -n api-service
curl https://api.lumbenlengo.com/health | python3 -m json.tool
```

Trigger KEDA scaling manually:

```bash
SQS_URL=$(terraform -chdir=terraform output -raw sqs_queue_url)

for i in $(seq 1 50); do
  aws sqs send-message \
    --queue-url "$SQS_URL" \
    --message-body "{\"item_id\":\"test-$i\",\"name\":\"Test Item $i\",\"priority\":5,\"created_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"action\":\"process_item\"}"
done

kubectl get pods -n worker-service -w
kubectl describe scaledobject worker-service -n worker-service
```

## Design decisions

<p align="center">
  <img src="https://github.com/user-attachments/assets/35e7d945-b97d-446f-b007-426e8acb08c4" alt="Diagrama EKS GitOps" style="width: 100%; max-width: 1000px; height: auto;" />
</p>

Every non obvious technical choice in this repository is written up as an ADR, including what was rejected and why:

[001, GitOps over imperative kubectl](docs/adr/001-gitops-over-imperative.md)
[002, IRSA over node IAM roles](docs/adr/002-irsa-over-node-role.md)
[003, KEDA over HPA for the worker](docs/adr/003-keda-over-hpa-worker.md)
[004, GitHub Actions OIDC over static IAM credentials](docs/adr/004-oidc-over-static-credentials.md)

## What I would build next

EKS Auto Mode instead of self managed node groups. Blue or green deployments for api-service. A service mesh (Istio or Linkerd) for mTLS between services. Kyverno policies for admission control. Cross region disaster recovery for DynamoDB and the Terraform state backend.

## About

Built and maintained by Patrício Lumbe.

[lumbenlengo.com](https://lumbenlengo.com) | [LinkedIn](https://linkedin.com/in/Lumbenlengo)
