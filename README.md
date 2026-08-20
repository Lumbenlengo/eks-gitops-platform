# eks-gitops-platform

<p>
  <img src="https://img.shields.io/badge/IaC-Terraform-844FBA?logo=terraform&logoColor=white" height="20">
  <img src="https://img.shields.io/badge/Cloud-AWS-FF9900?logo=amazonaws&logoColor=white" height="20">
  <img src="https://img.shields.io/badge/CI-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white" height="20">
  <img src="https://img.shields.io/badge/GitOps-ArgoCD-EF7B4D?logo=argo&logoColor=white" height="20">
  <img src="https://img.shields.io/badge/Autoscaling-KEDA-3F51B5?logo=kubernetes&logoColor=white" height="20">
</p>

<p>
  <img width="32" height="32" alt="Amazon EC2" src="https://github.com/user-attachments/assets/d0917868-b83b-4bbe-b0a2-967e169ed8ea" />
  <img width="32" height="32" alt="AWS Identity and Access Management (IAM)" src="https://github.com/user-attachments/assets/05b64da2-347c-4ec3-869d-c43ae6c3a31b" />
  <img width="32" height="32" alt="Amazon DynamoDB" src="https://github.com/user-attachments/assets/df976202-72ee-457b-b58f-9509d8ee2427" />
  <img width="32" height="32" alt="Amazon Route 53" src="https://github.com/user-attachments/assets/fe0d34b0-e237-46ea-942a-9483d7abc4af" />
  <img width="32" height="32" alt="Elastic Load Balancing (ELB)" src="https://github.com/user-attachments/assets/701f7251-1288-4bf5-ad96-8f00b486af7e" />
  <img width="32" height="32" alt="Amazon CloudWatch" src="https://github.com/user-attachments/assets/c43bbdee-c510-4c4b-8189-dfc972d34397" />
</p>

Amazon EKS platform where Terraform provisions the infrastructure, ArgoCD handles GitOps delivery, and workloads access AWS through short-lived credentials using OIDC federation instead of stored keys.

## Why I built this

I built this to go beyond a basic Kubernetes demo and practice the patterns I would expect to find in a real platform engineering environment: infrastructure fully defined in code, deployments driven by Git rather than by someone typing kubectl, and a worker that costs nothing while it has no work to do.

## The application

The platform runs a small e commerce style application so the infrastructure has a realistic workload to carry. The API is built with FastAPI and serves a storefront page and an operations dashboard. Orders placed through the API are published to SQS, and a separate worker consumes the queue and writes the results to DynamoDB.

The application itself is intentionally simple. It exists to give the platform something real to deploy, scale, and secure, not to demonstrate frontend work.

## What this demonstrates

Infrastructure as code with Terraform. GitOps delivery with ArgoCD. Zero static AWS credentials, using OIDC for CI and IRSA for pods. Event driven autoscaling with KEDA, including scale to zero. Multi AZ VPC architecture with public and private subnets across three Availability Zones. Observability with Prometheus and Grafana.

AWS · EKS · Terraform · Kubernetes · ArgoCD · GitHub Actions · Helm · KEDA · SQS · DynamoDB · Prometheus · Grafana · OIDC · IRSA

## Architecture

<p align="center">
  <img src="https://github.com/user-attachments/assets/95b0345f-d961-40c2-adf1-078078bfa72b" alt="Production-Grade Amazon EKS GitOps Platform - Architecture" style="width: 100%; max-width: 1400px; height: auto;" />
</p>

## Walkthrough

A 5 minute video covering the application, the GitOps deployment flow, the security model, and KEDA scaling in action.

[Watch the 5 minute walkthrough](#) (replace with your Loom link before publishing)

## How a deploy happens

```
git push  ->  GitHub Actions  ->  tests + Terraform plan  ->  build + Trivy scan
   ->  ECR  ->  Helm values.yaml bump  ->  ArgoCD  ->  EKS
```

1. CI runs the test suite with an 80 percent coverage gate, and on a pull request posts a Terraform plan for review.
2. On merge to main, CI builds the image, scans it with Trivy, pushes it to ECR, and bumps the tag in the Helm chart.
3. ArgoCD polls Git every 3 minutes, detects the change, and applies the Helm release as a rolling update, with a PodDisruptionBudget keeping at least one pod available throughout.

Nobody runs kubectl apply against production. The only path in is a Git commit.

## Security by design

1. GitHub Actions to AWS: OIDC federation, no long-lived access keys stored anywhere.
2. Pods to AWS: IRSA, each service assumes its own scoped IAM role through a projected OIDC token, using short-lived credentials instead of stored keys.
3. Container security: every image is scanned with Trivy, and the build fails on CRITICAL vulnerabilities.

Full reasoning and the alternatives I rejected are in [ADR 002](docs/adr/002-irsa-over-node-role.md) and [ADR 004](docs/adr/004-oidc-over-static-credentials.md).

## Scaling

api-service scales on CPU through a standard HPA, 2 to 10 pods. worker-service scales on SQS queue depth through KEDA, 0 to 20 pods. CPU is a lagging signal for a queue consumer, it stays low right up until a burst of messages needs processing, so KEDA reading the queue directly reacts sooner. When the queue is empty the worker runs zero pods, not a padded minimum kept warm just in case.

The comparison against a plain HPA is in [ADR 003](docs/adr/003-keda-over-hpa-worker.md).

## Observability

Prometheus and Grafana run through kube-prometheus-stack, with a ServiceMonitor per service. Application and VPC Flow Logs go to CloudWatch with 30 day retention.

## Cost awareness

Baseline cost is roughly $258/month when the environment is running, mainly from the EKS control plane, EC2 nodes, ALB, and three NAT Gateways. I don't keep the environment running continuously, I provision it when I need to demo or extend the platform. Full breakdown, including the single NAT Gateway option for dev and test, is in [docs/cost-analysis.md](docs/cost-analysis.md).

## Design decisions

Every non obvious technical choice is written up as an ADR, including what I rejected and why.

[001, GitOps over imperative kubectl](docs/adr/001-gitops-over-imperative.md)
[002, IRSA over node IAM roles](docs/adr/002-irsa-over-node-role.md)
[003, KEDA over HPA for the worker](docs/adr/003-keda-over-hpa-worker.md)
[004, GitHub Actions OIDC over static IAM credentials](docs/adr/004-oidc-over-static-credentials.md)

## Run it yourself

Requirements: AWS CLI 2.15+, Terraform 1.7+, kubectl 1.29+, Helm 3.14+, ArgoCD CLI 2.10+.

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

$(terraform output -raw configure_kubectl)
kubectl get nodes -o wide
```

The full setup, including the Terraform state backend bootstrap, the ArgoCD bootstrap, and how to verify the GitOps and KEDA scaling loops end to end, is in [docs/deployment.md](docs/deployment.md).

## What I would build next

EKS Auto Mode, blue or green deployments, and Kyverno admission policies.

## About

Built and maintained by Patrício Lumbe.

[patriciolumbe.com](https://patriciolumbe.com) | [LinkedIn](https://linkedin.com/in/Lumbenlengo)
