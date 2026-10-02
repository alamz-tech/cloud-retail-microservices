# Secure 3-Tier Microservices Platform on Amazon EKS
### Production-Grade Infrastructure, Dynamic Spot Autoscaling, and Zero-Trust Platform Security

[![Kubernetes](https://img.shields.io/badge/Kubernetes-EKS%201.30-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Terraform](https://img.shields.io/badge/Terraform-1.5+-844FBA?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Karpenter](https://img.shields.io/badge/Karpenter-v1.0+-00B4D8?logo=amazon-aws&logoColor=white)](https://karpenter.sh/)
[![External%20Secrets](https://img.shields.io/badge/External%20Secrets-v0.9+-black?logo=kubernetes&logoColor=white)](https://external-secrets.io/)
[![AWS%20ALB](https://img.shields.io/badge/AWS-ALB%20Controller-FF9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com/elasticloadbalancing/)
[![PostgreSQL](https://img.shields.io/badge/RDS-PostgreSQL%2016-336791?logo=postgresql&logoColor=white)](https://aws.amazon.com/rds/)

---

## 1. Executive Summary & Architecture Overview

This repository contains the complete Infrastructure as Code (IaC) and cloud-native platform manifests for deploying an enterprise-grade, cost-optimized, 3-tier retail microservices platform on **Amazon Elastic Kubernetes Service (EKS)**.

The platform is designed following **Zero-Trust Security Principles**, **Least-Privilege Identity Management (IRSA)**, and **FinOps Cloud Budget Optimization**.

```
                                      INTERNET
                                         │
                                         ▼
                     ┌────────────────────────────────────────┐
                     │    AWS Application Load Balancer       │  (Managed by AWS Load
                     │       (Internet-Facing Ingress)        │   Balancer Controller)
                     └───────────────────┬────────────────────┘
                                         │ HTTP :80
                                         ▼
       ┌─────────────────────────────────────────────────────────────────────────┐
       │ Kubernetes Namespace: frontend                                          │
       │                                                                         │
       │   ┌────────────────────────────────────────────────────────┐            │
       │   │ Pod: frontend-ui (2 Replicas)                          │            │
       │   │  • Unprivileged NGINX (UID 101, non-root, drop ALL)    │            │
       │   │  • Serves React 18 SPA static assets                   │            │
       │   │  • Reverse-proxies /api/* to internal cluster DNS      │            │
       │   └───────────────────────────┬────────────────────────────┘            │
       └───────────────────────────────┼─────────────────────────────────────────┘
                                       │ Private Cluster DNS:
                                       │ http://backend-api.backend.svc.cluster.local:8000
                                       ▼
       ┌─────────────────────────────────────────────────────────────────────────┐
       │ Kubernetes Namespace: backend                                           │
       │   [NetworkPolicy: Drops 100% of ingress unless from frontend namespace] │
       │                                                                         │
       │   ┌────────────────────────────────────────────────────────┐            │
       │   │ Pod: backend-api (2 Replicas)                          │            │
       │   │  • Python 3.11 FastAPI (UID 10001, drop ALL cap)       │            │
       │   │  • Auto-seeds 3 initial retail items on startup        │            │
       │   │  • Secrets injected securely from AWS Secrets Manager  │            │
       │   └───────────────────────────┬────────────────────────────┘            │
       └───────────────────────────────┼─────────────────────────────────────────┘
                                       │
                    ┌──────────────────┴──────────────────┐
                    │                                     │
                    ▼                                     ▼
     ┌───────────────────────────────┐     ┌───────────────────────────────┐
     │ AWS Secrets Manager           │     │ Amazon RDS PostgreSQL 16      │
     │ retail-app/rds/credentials    │     │ Private Subnet (Non-public)   │
     │ (Synced via External Secrets) │     │ db.t4g.micro / Port 5432      │
     └───────────────────────────────┘     └───────────────────────────────┘
```

---

## 2. Core Platform Capabilities & Innovations

| Pillar | Implementation | Technical Benefit |
| :--- | :--- | :--- |
| **FinOps & Spot Scaling** | **Karpenter v1.0+** with `NodePool` & `EC2NodeClass` | Dynamically provisions burstable EC2 Spot instances (`t3.small`, `t3.medium`) for worker workloads, achieving up to 90% cost savings over on-demand rates. |
| **Secret Management** | **External Secrets Operator (ESO)** | Zero secrets stored in Git or plaintext. Synchronizes JSON credentials directly from AWS Secrets Manager to native Kubernetes Secrets with automated rotation. |
| **Identity & Access** | **IAM Roles for Service Accounts (IRSA)** | Pods assume fine-grained AWS IAM roles via OIDC WebIdentity federation without static AWS access keys or node-level shared credentials. |
| **Network Isolation** | **VPC CNI Network Policy Agent** | Hardware-level pod network isolation. Drops all unauthorized traffic to `backend-api` on port 8000 unless originating from pods in the `frontend` namespace. |
| **Ingress Architecture** | **AWS Load Balancer Controller** | Provisions an Application Load Balancer in public subnets with IP target routing directly to unprivileged frontend pods. Backend remains completely private. |
| **Database Isolation** | **Private Amazon RDS (db.t4g.micro)** | Multi-AZ ready, placed in isolated database subnets without Internet or NAT routing. Security groups allow ingress on TCP 5432 strictly from EKS node security groups. |

---

## 3. IAM Roles for Service Accounts (IRSA) Least-Privilege Matrix

To satisfy enterprise compliance and strict least-privilege access control, all Kubernetes components authenticate using AWS IAM Roles for Service Accounts (IRSA):

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                 IRSA SECURITY MATRIX                                   │
├───────────────────────────────┬─────────────────────────┬──────────────────────────────┤
│ Kubernetes Component          │ ServiceAccount          │ AWS IAM Policy Scope         │
├───────────────────────────────┼─────────────────────────┼──────────────────────────────┤
│ External Secrets Operator     │ external-secrets:       │ secretsmanager:GetSecretValue│
│ (ESO) Controller              │ external-secrets        │ secretsmanager:DescribeSecret│
│                               │                         │ Resource: retail-app/rds/*   │
├───────────────────────────────┼─────────────────────────┼──────────────────────────────┤
│ AWS Load Balancer Controller  │ kube-system:            │ AWSLoadBalancerController    │
│                               │ aws-load-balancer-ctrl  │ Limited to VPC & ALBs        │
├───────────────────────────────┼─────────────────────────┼──────────────────────────────┤
│ Karpenter Autoscaler          │ karpenter:              │ ec2:RunInstances, Fleet,     │
│ Controller                    │ karpenter               │ PassRole to Node Role, SQS   │
├───────────────────────────────┼─────────────────────────┼──────────────────────────────┤
│ Karpenter Node Instance       │ IAM Instance Profile    │ WorkerNodePolicy, CNI_Policy,│
│ (EC2 Worker Nodes)            │ (cloud-retail-karpenter)│ ECRReadOnly, SSMManagedCore  │
└───────────────────────────────┴─────────────────────────┴──────────────────────────────┘
```

---

## 4. Repository Structure

```text
.
├── infrastructure/               # Terraform Infrastructure Code
│   ├── versions.tf               # Terraform & Provider configurations
│   ├── variables.tf              # Configurable input parameters
│   ├── vpc.tf                    # Custom VPC, 3-tier subnets, IGW & NAT Gateway
│   ├── eks.tf                    # EKS Cluster, OIDC provider, Addons & Node Group
│   ├── karpenter.tf              # Karpenter IAM roles, SQS interruption & EC2 profile
│   ├── rds.tf                    # Amazon RDS PostgreSQL db.t4g.micro & security group
│   ├── secrets_manager.tf        # AWS Secrets Manager secret & JSON version
│   ├── irsa.tf                   # ECR repositories & IRSA policies (ESO, ALB Controller)
│   ├── helm_controllers.tf       # Helm releases for Karpenter, ESO, ALB Controller
│   ├── outputs.tf                # Cluster endpoints, role ARNs, database host
│   └── terraform.tfvars.example  # Sample variable overrides
├── manifests/                    # Kubernetes Platform & Application Manifests
│   ├── karpenter/
│   │   ├── nodepool.yaml         # Spot instance pool (t3.small, t3.medium)
│   │   └── ec2nodeclass.yaml     # Subnet and SecurityGroup discovery spec
│   ├── eso/
│   │   └── cluster-secret-store.yaml # ClusterSecretStore targeting AWS Secrets Manager
│   ├── backend/
│   │   ├── namespace.yaml        # 'backend' namespace
│   │   ├── external-secret.yaml  # ESO secret sync manifest
│   │   ├── deployment.yaml       # Python FastAPI deployment (UID 10001)
│   │   ├── service.yaml          # ClusterIP service (:8000)
│   │   └── network-policy.yaml   # Ingress lockdown (frontend only)
│   └── frontend/
│       ├── namespace.yaml        # 'frontend' namespace
│       ├── deployment.yaml       # Rootless NGINX deployment (UID 101)
│       ├── service.yaml          # ClusterIP service (:80 -> :8080)
│       └── ingress.yaml          # AWS ALB Ingress specification
├── scripts/                      # Operational Automation Scripts
│   ├── build-and-push.sh         # Docker multi-stage build and ECR push
│   ├── deploy.sh                 # Full platform deployment orchestrator
│   ├── verify.sh                 # Comprehensive validation test suite
│   └── teardown.sh               # Graceful cloud teardown (FinOps spin-and-kill)
├── frontend-ui/                  # React 18 + Vite frontend source & Dockerfile
├── backend-api/                  # FastAPI + SQLAlchemy backend source & Dockerfile
├── EVIDENCE.md                   # Capstone verification proofs and terminal logs
├── VIDEO_WALKTHROUGH_SCRIPT.md   # Presentation script for grading demonstration
└── README.md
```

---

## 5. Hands-On Step-by-Step Operator Runbook

> [!TIP]
> For the complete, detailed command reference with expected outputs and architecture diagnostics for every individual stage, see [STEP_BY_STEP_RUNBOOK.md](STEP_BY_STEP_RUNBOOK.md).

### Stage 1: Build & Push Containers to Amazon ECR
```bash
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# Login to private ECR
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create repos (if needed)
aws ecr create-repository --repository-name retail-frontend --region ${AWS_REGION} || true
aws ecr create-repository --repository-name retail-backend --region ${AWS_REGION} || true

# Build & Push Frontend (Vite React SPA -> Rootless NGINX)
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-frontend:v1 ./frontend-ui
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-frontend:v1

# Build & Push Backend (Python FastAPI -> Non-root UID 10001)
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-backend:v1 ./backend-api
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-backend:v1
```

### Stage 2: Infrastructure Provisioning (Terraform Plan & Apply)
```bash
cd infrastructure
terraform init
terraform plan       # Inspect VPC, EKS, RDS, Secrets Manager, and IRSA roles
terraform apply -auto-approve
terraform output     # Inspect RDS host, cluster name, and role ARNs
cd ..
```

### Stage 3: Cluster Authentication
```bash
aws eks update-kubeconfig --name cloud-retail-eks --region us-east-1
kubectl get nodes
```

### Stage 4: Deploy Platform Controllers via Helm CLI
```bash
# 1. External Secrets Operator (ESO)
helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets
ESO_ROLE_ARN=$(terraform -chdir=infrastructure output -raw eso_role_arn)
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --set installCRDs=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ESO_ROLE_ARN}"

# 2. AWS Load Balancer Controller
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
ALB_ROLE_ARN=$(terraform -chdir=infrastructure output -raw alb_controller_role_arn)
VPC_ID=$(aws eks describe-cluster --name cloud-retail-eks --region us-east-1 --query "cluster.resourcesVpcConfig.vpcId" --output text)
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${ALB_ROLE_ARN}
EOF
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=cloud-retail-eks \
  --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1 --set vpcId=${VPC_ID}

# 3. Karpenter Spot Autoscaler
KARPENTER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/cloud-retail-eks-karpenter-controller-role"
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "1.0.1" -n karpenter --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${KARPENTER_ROLE_ARN}" \
  --set settings.clusterName=cloud-retail-eks \
  --set settings.interruptionQueue=cloud-retail-eks-karpenter

# Apply Karpenter Spot NodePool and EC2NodeClass
kubectl apply -f manifests/karpenter/ec2nodeclass.yaml
kubectl apply -f manifests/karpenter/nodepool.yaml
```

### Stage 5: Configure Secrets Integration (ESO & RDS)
```bash
kubectl apply -f manifests/eso/cluster-secret-store.yaml
kubectl apply -f manifests/backend/namespace.yaml
kubectl apply -f manifests/backend/external-secret.yaml

# Verify Secret synchronization
kubectl get externalsecrets -n backend
kubectl get secret rds-credentials -n backend
```

### Stage 6: Deploy Microservices & Ingress
```bash
# Backend Deployment & Service
kubectl apply -f manifests/backend/deployment.yaml
kubectl apply -f manifests/backend/service.yaml
kubectl logs -n backend -l app=backend-api --tail=30  # Confirms DB auto-seeding

# Frontend Deployment, Service, and ALB Ingress
kubectl apply -f manifests/frontend/namespace.yaml
kubectl apply -f manifests/frontend/deployment.yaml
kubectl apply -f manifests/frontend/service.yaml
kubectl apply -f manifests/frontend/ingress.yaml

# Retrieve Public ALB URL
kubectl get ingress -n frontend retail-frontend-ingress
```

### Stage 7: Network Policy & Security Verification
```bash
kubectl apply -f manifests/backend/network-policy.yaml

# Test A (Blocked): Curl from default namespace (times out)
kubectl run curl-test --image=curlimages/curl -n default -i --tty --rm -- \
  curl -m 4 http://backend-api.backend.svc.cluster.local:8000/api/health

# Test B (Allowed): Query from frontend pod (returns 200 OK)
FRONTEND_POD=$(kubectl get pods -n frontend -l app=frontend-ui -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n frontend -it $FRONTEND_POD -- wget -qO- http://backend-api.backend.svc.cluster.local:8000/api/health
```

### Stage 8: Clean Cloud Teardown (FinOps Credit Protection)
```bash
# Release ALB and remove workloads
kubectl delete ingress retail-frontend-ingress -n frontend
sleep 30
kubectl delete namespace frontend backend

# Destroy AWS Cloud Infrastructure
cd infrastructure
terraform destroy -auto-approve
```

*(Optional shortcut: Run `./scripts/deploy.sh`, `./scripts/verify.sh`, and `./scripts/teardown.sh` if you prefer automated script execution).*


## 6. Verification Proofs Summary

| Check | Command | Expected Result |
| :--- | :--- | :--- |
| **Spot Nodes** | `kubectl get nodes -L karpenter.sh/capacity-type` | Shows `karpenter.sh/capacity-type: spot` |
| **External Secrets** | `kubectl get externalsecrets -A` | `STATUS: SecretSynced`, `READY: True` |
| **Blocked Ingress** | `kubectl run curl-test ... -n default` | `curl: (28) Connection timed out` |
| **Allowed Ingress** | `kubectl exec -n frontend ... wget` | `{"status":"healthy","database":"connected"}` |
| **Teardown** | `terraform destroy -auto-approve` | `Destroy complete! Resources: 38 destroyed.` |

Detailed terminal logs and screenshots are documented in [EVIDENCE.md](file:///Users/husseinalamutu/.gemini/antigravity/scratch/cloud-retail-microservices/EVIDENCE.md).

---

## 7. Automated CI/CD Pipeline & GitHub Actions OIDC

To eliminate manual deployment steps in production, this repository includes an enterprise-grade CI/CD pipeline powered by **GitHub Actions** and **AWS OpenID Connect (OIDC)** identity federation:

### Architecture: Keyless Continuous Delivery
```
Developer Commit / PR
         │
         ▼
[ GitHub Actions CI Gate ]
├── Flake8 Syntax & Code Standards
├── Pytest Automated Unit Tests
├── Frontend React Vite Build Validation
├── Terraform Format & Validate
└── Kubernetes Manifest Client Dry-Run
         │ (Merge to main)
         ▼
[ GitHub Actions CD Delivery ]
├── AWS OIDC WebIdentity Federation (No static keys in GitHub!)
├── Docker Buildx (linux/amd64) with GitHub Actions Layer Caching
├── Push to Amazon ECR (Tagged with Git Commit SHA)
├── Rolling Update on Amazon EKS (kubectl set image)
├── Rollout Status Verification (kubectl rollout status)
└── Automated Smoke Test against Live AWS Application Load Balancer
```

### Key Workflows
* **`ci.yaml` (PR Quality Gate):** Triggers on all pull requests targeting `main`. Rejects non-compliant code before merge.
* **`cd.yaml` (Production Delivery):** Triggers on merges to `main`. Assumes the `cloud-retail-eks-github-actions-role` via AWS STS OIDC, pushes immutable images to ECR, executes zero-downtime rolling updates on EKS, and runs live smoke tests against the Application Load Balancer.

### Student Assignment Brief
The formal student project brief for this module is available as:
* 📄 **Microsoft Word Format:** [`Capstone_Project_Brief_CICD_EKS.docx`](file:///Users/husseinalamutu/.gemini/antigravity/scratch/cloud-retail-microservices/Capstone_Project_Brief_CICD_EKS.docx)
* 🌐 **HTML Format:** [`Capstone_Project_Brief_CICD_EKS.html`](file:///Users/husseinalamutu/.gemini/antigravity/scratch/cloud-retail-microservices/Capstone_Project_Brief_CICD_EKS.html)
