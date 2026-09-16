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

## 5. Step-by-Step Operator Runbook

### Step 1: Authentication & Docker Setup
Ensure your AWS credentials and Docker daemon are active:
```bash
# Verify AWS credentials
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "Deploying into AWS Account: ${AWS_ACCOUNT_ID} in ${AWS_REGION}"

# Launch Docker Desktop if not running
open -a Docker
```

### Step 2: Zero-Code Container Packaging
Build and push both microservice containers to private Amazon ECR:
```bash
./scripts/build-and-push.sh
```

### Step 3: Infrastructure Provisioning (Terraform)
Apply the infrastructure code to provision VPC, EKS, RDS, and Controllers:
```bash
cd infrastructure
terraform init
terraform apply -auto-approve
```

### Step 4: Workload Deployment
Deploy Karpenter NodePools, ExternalSecrets, and microservices:
```bash
cd ..
./scripts/deploy.sh
```

### Step 5: Verification & Testing
Execute the complete test suite to validate Spot node scaling, ESO secret sync, network policy isolation, and ALB ingress:
```bash
./scripts/verify.sh
```

### Step 6: FinOps Teardown ("Spin-and-Kill Routine")
To prevent credit consumption when you finish testing:
```bash
./scripts/teardown.sh
```

---

## 6. Verification Proofs Summary

| Check | Command | Expected Result |
| :--- | :--- | :--- |
| **Spot Nodes** | `kubectl get nodes -L karpenter.sh/capacity-type` | Shows `karpenter.sh/capacity-type: spot` |
| **External Secrets** | `kubectl get externalsecrets -A` | `STATUS: SecretSynced`, `READY: True` |
| **Blocked Ingress** | `kubectl run curl-test ... -n default` | `curl: (28) Connection timed out` |
| **Allowed Ingress** | `kubectl exec -n frontend ... wget` | `{"status":"healthy","database":"connected"}` |
| **Teardown** | `terraform destroy -auto-approve` | `Destroy complete! Resources: 38 destroyed.` |

Detailed terminal logs and screenshots are documented in [EVIDENCE.md](file:///Users/husseinalamutu/.gemini/antigravity/scratch/cloud-retail-microservices/EVIDENCE.md).
