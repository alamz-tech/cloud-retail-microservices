# Cloud Retail Microservices Platform

[![Kubernetes](https://img.shields.io/badge/Kubernetes-EKS%201.29+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Docker](https://img.shields.io/badge/Docker-Multi--Stage-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.110+-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![React](https://img.shields.io/badge/React-18-61DAFB?logo=react&logoColor=black)](https://react.dev/)
[![NGINX](https://img.shields.io/badge/NGINX-Unprivileged-009639?logo=nginx&logoColor=white)](https://nginx.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-RDS%2016-336791?logo=postgresql&logoColor=white)](https://aws.amazon.com/rds/)

A production-ready 3-tier microservices workload engineered for the **Amazon EKS DevOps/Platform Engineering Capstone Project**.

Designed specifically for platform and DevOps engineers who want zero-friction container packaging: **Docker handles 100% of compilation and dependency management**, and the backend database **automatically creates its schema and seeds dummy retail items on startup**.

---

## Architecture Overview

```text
                                 INTERNET
                                    │
                                    ▼
                     ┌─────────────────────────────┐
                     │ AWS Application Load Balancer│ (ALB Ingress)
                     └──────────────┬──────────────┘
                                    │ HTTP :80
                                    ▼
       ┌────────────────────────────────────────────────────────┐
       │ Kubernetes Namespace: frontend                         │
       │                                                        │
       │   ┌──────────────────────────────────────────────┐     │
       │   │ Pod: frontend-ui (NGINX Unprivileged :8080)  │     │
       │   │  • Serves React 18 SPA static bundle         │     │
       │   │  • Reverse proxies /api/* to internal DNS   │     │
       │   └──────────────────────┬───────────────────────┘     │
       └──────────────────────────┼─────────────────────────────┘
                                  │ Private K8s DNS:
                                  │ http://backend-api.backend.svc.cluster.local:8000
                                  ▼
       ┌────────────────────────────────────────────────────────┐
       │ Kubernetes Namespace: backend                          │
       │   [NetworkPolicy: Ingress restricted to frontend pods] │
       │                                                        │
       │   ┌──────────────────────────────────────────────┐     │
       │   │ Pod: backend-api (FastAPI Python 3.11 :8000) │     │
       │   │  • Non-root runtime (UID 10001)              │     │
       │   │  • Auto-seeds catalog items on startup       │     │
       │   └──────────────────────┬───────────────────────┘     │
       └──────────────────────────┼─────────────────────────────┘
                                  │
               ┌──────────────────┴──────────────────┐
               │                                     │
               ▼                                     ▼
┌───────────────────────────────┐     ┌───────────────────────────────┐
│ AWS Secrets Manager           │     │ Amazon RDS (PostgreSQL)       │
│ retail-app/rds/credentials    │     │ Private Database Subnet       │
│ (Synced via External Secrets) │     │ db.t4g.micro / port 5432      │
└───────────────────────────────┘     └───────────────────────────────┘
```

---

## Repository Structure

```text
cloud-retail-microservices/
├── frontend-ui/
│   ├── src/                     # Simple, clean React single-page UI
│   │   ├── App.jsx              # Dashboard UI, metrics, catalog table, & error state
│   │   ├── main.jsx             # React DOM root mounting
│   │   └── index.css            # Clean responsive stylesheet (no external CSS dependencies)
│   ├── index.html               # Web page entrypoint
│   ├── package.json             # NPM project definitions
│   ├── vite.config.js           # Vite configuration
│   ├── nginx.conf               # Hardened unprivileged NGINX with reverse proxy to backend
│   ├── Dockerfile               # Multi-stage build (Node 20 build -> NGINX Alpine)
│   └── k8s/
│       ├── deployment.yaml      # Non-root deployment, dropped Linux capabilities
│       ├── service.yaml         # ClusterIP service (port 80 -> 8080)
│       ├── ingress.yaml         # AWS ALB Ingress configuration
│       └── namespace.yaml       # 'frontend' namespace
├── backend-api/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py              # FastAPI service connecting to PostgreSQL
│   │   ├── database.py          # SQLAlchemy setup and auto-seeding
│   │   └── models.py            # SQLAlchemy models
│   ├── requirements.txt         # Production Python dependencies
│   ├── Dockerfile               # Multi-stage non-root Python build (UID 10001)
│   └── k8s/
│       ├── deployment.yaml      # Hardened deployment with ESO secret injection
│       ├── service.yaml         # ClusterIP service (port 8000)
│       ├── external-secret.yaml # ESO Custom Resource to fetch RDS credentials
│       ├── network-policy.yaml  # Network isolation: drops non-frontend traffic
│       └── namespace.yaml       # 'backend' namespace
├── EVIDENCE.md                  # Deliverable 2 evidence template
├── .gitignore
└── README.md
```

---

## Component Specifications

### 1. Frontend (`frontend-ui`)
* **Framework:** Lightweight React using Vite.
* **Functionality:**
  * A header that says `"Cloud Retail Internal Dashboard"`.
  * A card showing live data fetched from `/api/products` (retrieved from the backend).
  * Clear error states if the backend or database is unreachable.
* **NGINX Configuration (`nginx.conf`):**
  * Runs as an unprivileged user on port `8080`.
  * Serves compiled static assets from `/usr/share/nginx/html`.
  * Includes a reverse proxy block forwarding `/api/` requests to the internal Kubernetes DNS name of the backend (`http://backend-api.backend.svc.cluster.local:8000/api/`). This avoids CORS issues and keeps the backend private.
* **Dockerfile:**
  * Stage 1: `node:20-alpine` runs `npm install` and `npm run build`.
  * Stage 2: `nginxinc/nginx-unprivileged:alpine` copies `/dist` output and runs rootless.
* **Kubernetes Manifests (`frontend-ui/k8s/`):**
  * `deployment.yaml`: Namespace `frontend`, securityContext dropping all Linux capabilities, containerPort `8080`.
  * `service.yaml`: `ClusterIP` exposing port `80` targeting `8080`.
  * `ingress.yaml`: Ingress manifest with annotations for the AWS Load Balancer Controller (`kubernetes.io/ingress.class: alb`, `alb.ingress.kubernetes.io/scheme: internet-facing`, `alb.ingress.kubernetes.io/target-type: ip`).

### 2. Backend (`backend-api`)
* **Framework:** Python FastAPI with `SQLAlchemy` and `psycopg2-binary`.
* **Endpoints:**
  * `GET /api/health`: Health probe endpoint.
  * `GET /api/products`: Queries a PostgreSQL database table named `products` and returns catalog items (e.g., ID, name, price, stock).
* **Database Auto-Seeding (CRITICAL):**
  * The student does NOT know how to run SQL migrations.
  * In `main.py` or `database.py`, use `Base.metadata.create_all(bind=engine)` on startup to automatically create the table.
  * Immediately check if the table is empty. If it is, automatically insert 3 dummy retail products:
    1. **Mechanical Keyboard** ($129.99, Stock: 45)
    2. **Wireless Mouse** ($49.99, Stock: 120)
    3. **USB-C Hub** ($34.50, Stock: 80)
* **Configuration:**
  * Reads DB host, user, password, and name from environment variables (`DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`).
* **Dockerfile:**
  * Multi-stage build using `python:3.11-slim`.
  * Runs as non-root user `appuser` (`UID 10001`).
  * No development dependencies in final image.
* **Kubernetes Manifests (`backend-api/k8s/`):**
  * `deployment.yaml`: Namespace `backend`, rootless security context.
  * `service.yaml`: Internal `ClusterIP` on port `8000`.
  * `external-secret.yaml`: Manifest targeting an AWS Secrets Manager secret named `retail-app/rds/credentials` to inject database variables (`DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`).

---

# Capstone Project: Secure 3-Tier Microservices Platform on EKS

## 1. Project Overview
In this capstone, you will act as a Senior Platform Engineer. You are tasked with taking an internal product team's microservices and deploying them onto an enterprise-grade, cost-optimized Amazon EKS platform using Terraform, Docker, and native Kubernetes controllers.
You will provision the infrastructure, build hardened containers, set up dynamic Spot node scaling, securely inject Amazon RDS credentials using the External Secrets Operator, and route internet traffic exclusively to the frontend via an AWS Application Load Balancer.

> **Scope Note:** This project focuses strictly on infrastructure-as-code, platform security, and container orchestration. CI/CD pipelines are intentionally out of scope.

## 2. Workload Repository
The application codebase provided by the product team is located here:
* **Repository:** [https://github.com/alamz-tech/cloud-retail-microservices](https://github.com/alamz-tech/cloud-retail-microservices)

The repository contains:
* **`frontend-ui/`**: A React single-page dashboard configured with an unprivileged NGINX web server.
* **`backend-api/`**: A Python FastAPI microservice that queries an Amazon RDS PostgreSQL database.

## 3. Cloud Budget & Credit Protection (FinOps)
Amazon EKS costs $0.10 per hour (~$73/month) for the managed control plane. To ensure you stay well within your AWS credit balance, follow these operational rules:
* **The Spin-and-Kill Routine:** Never leave your cluster or RDS database running overnight. Run `terraform apply` when you begin working, test your configuration, and run `terraform destroy` when you are done for the day. A 3-hour session costs less than $0.45.
* **Spot Instances via Karpenter:** Worker nodes must be provisioned as EC2 Spot instances (`t3.small` / `t3.medium`). Spot instances offer up to 90% cost savings over on-demand pricing.
* **Database Sizing:** Provision RDS PostgreSQL as `db.t4g.micro` with 20GB storage to minimize hourly database costs.

## 4. Student Integration Guide (Step-by-Step)

### Step 1: Zero-Code Container Packaging
You do not need Node.js, npm, or Python installed on your local machine. Both applications use Docker multi-stage builds, meaning Docker compiles and packages everything in an isolated sandbox.

Clone the application repo:
```bash
git clone https://github.com/alamz-tech/cloud-retail-microservices.git
cd cloud-retail-microservices
```

Build and tag the containers locally:
```bash
# Build the frontend (compiles React and packages into NGINX rootless)
docker build -t <your-aws-account-id>.dkr.ecr.<region>.amazonaws.com/retail-frontend:v1 ./frontend-ui

# Build the backend (packages FastAPI in non-root Python runtime)
docker build -t <your-aws-account-id>.dkr.ecr.<region>.amazonaws.com/retail-backend:v1 ./backend-api
```

Authenticate Docker to Amazon ECR and push both images to your private ECR repositories:
```bash
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <your-aws-account-id>.dkr.ecr.<region>.amazonaws.com

docker push <your-aws-account-id>.dkr.ecr.<region>.amazonaws.com/retail-frontend:v1
docker push <your-aws-account-id>.dkr.ecr.<region>.amazonaws.com/retail-backend:v1
```

### Step 2: Infrastructure Provisioning (Terraform)
Navigate to your personal infrastructure repository and execute your Terraform code to provision:
* A custom VPC with dedicated public and private subnets.
* An Amazon RDS PostgreSQL instance placed securely in the private database subnets.
* An Amazon Secrets Manager secret storing the database connection string and password (`retail-app/rds/credentials`).
* An Amazon EKS cluster with the OIDC identity provider enabled for IAM Roles for Service Accounts (IRSA).

### Step 3: Secrets Integration with ESO
To ensure zero secrets are hardcoded in git or plain text:
1. Deploy the External Secrets Operator using its official Helm chart:
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm repo update
   helm install external-secrets external-secrets/external-secrets \
     -n external-secrets \
     --create-namespace \
     --set installCRDs=true
   ```
2. Configure a `SecretStore` (or `ClusterSecretStore`) that uses an AWS IAM role (via IRSA) with read access to Secrets Manager.
3. Apply the `ExternalSecret` manifest in the backend namespace. It will automatically read the RDS credentials from Secrets Manager and generate a native Kubernetes Secret:
   ```bash
   kubectl apply -f backend-api/k8s/namespace.yaml
   kubectl apply -f backend-api/k8s/external-secret.yaml
   ```
4. Verify secret synchronization:
   ```bash
   kubectl get externalsecrets -n backend
   # Must show STATUS: SecretSynced
   kubectl get secret rds-credentials -n backend
   ```
The backend deployment will inject these credentials into its environment variables (`DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`).

### Step 4: Ingress & Traffic Flow
To keep the backend private while allowing the public to use the app:
1. Install the AWS Load Balancer Controller in your cluster via Helm:
   ```bash
   helm repo add eks https://aws.github.io/eks-charts
   helm repo update
   helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
     -n kube-system \
     --set clusterName=<your-cluster-name> \
     --set serviceAccount.create=false \
     --set serviceAccount.name=aws-load-balancer-controller
   ```
2. Deploy the backend service:
   ```bash
   kubectl apply -f backend-api/k8s/deployment.yaml
   kubectl apply -f backend-api/k8s/service.yaml
   ```
3. The `frontend-ui` NGINX container is pre-configured to reverse-proxy any request sent to `/api/*` to the internal backend Kubernetes DNS: `http://backend-api.backend.svc.cluster.local:8000/api/`
4. Apply the `ingress.yaml` in the frontend namespace. The AWS Load Balancer Controller will automatically provision an internet-facing Application Load Balancer (ALB) pointing only to the frontend service:
   ```bash
   kubectl apply -f frontend-ui/k8s/namespace.yaml
   kubectl apply -f frontend-ui/k8s/deployment.yaml
   kubectl apply -f frontend-ui/k8s/service.yaml
   kubectl apply -f frontend-ui/k8s/ingress.yaml
   ```
5. Retrieve the public Application Load Balancer address:
   ```bash
   kubectl get ingress -n frontend
   ```

### Step 5: Network Isolation & Security Hardening
Create a Kubernetes NetworkPolicy inside the backend namespace that drops all incoming traffic except connections originating from pods in the frontend namespace:
```bash
kubectl apply -f backend-api/k8s/network-policy.yaml
```

Verify that neither the backend service nor the RDS database has a public IP address:
```bash
# 1. Spawn a test pod in the DEFAULT namespace (Blocked by NetworkPolicy)
kubectl run curl-test --image=curlimages/curl -n default -i --tty --rm -- \
  curl -m 4 http://backend-api.backend.svc.cluster.local:8000/api/health

# 2. Test curl from a pod in the FRONTEND namespace (Allowed)
kubectl exec -n frontend -it $(kubectl get pods -n frontend -l app=frontend-ui -o jsonpath='{.items[0].metadata.name}') -- \
  wget -qO- http://backend-api.backend.svc.cluster.local:8000/api/health
```

---

## 5. What You Must Submit (Deliverables)
Because you must run `terraform destroy` after finishing to protect your AWS credit pool, do not submit a live website link.
Submit the following 3 deliverables for grading:

### Deliverable 1: Source Code Repository (GitHub)
Provide the link to your personal GitHub repository containing:
* `infrastructure/`: Your complete Terraform code (`vpc`, `eks`, `rds`, `irsa`, `karpenter`).
* `manifests/`: Your Kubernetes resources (`Deployment`, `Service`, `Ingress`, `ExternalSecret`, `NetworkPolicy`).
* `README.md`: A summary of your platform architecture and how you configured IRSA least privilege.

### Deliverable 2: Evidence Document (EVIDENCE.md)
Add an `EVIDENCE.md` file to the root of your repository containing terminal outputs or screenshots showing:
* **Spot Capacity Verification:** `kubectl get nodes -L karpenter.sh/capacity-type` (Must show worker nodes running on spot).
* **External Secrets Sync:** `kubectl get externalsecrets -A` (Must show STATUS: SecretSynced).
* **Network Isolation Proof:** A terminal snippet running a curl test from a test pod showing that unauthorized namespaces cannot reach the backend service.
* **Clean Cloud Teardown:** A terminal output showing the completion line of your teardown: `Destroy complete! Resources: X destroyed.`

### Deliverable 3: Video Walkthrough (3 to 5 Minutes)
Submit a link to an unlisted YouTube, Loom, or Drive video showing:
* Your cluster nodes and pods running healthy (`kubectl get pods -A`).
* Opening the public ALB address in your browser to show the frontend loading live data queried from the RDS database.
* Executing a quick `kubectl exec` command inside a pod to demonstrate that network policy boundaries are enforced.
* Running `terraform destroy` in your terminal to demonstrate cost-conscious cloud management.
