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
│       └── ingress.yaml         # AWS ALB Ingress configuration
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
│       └── external-secret.yaml # ESO Custom Resource to fetch RDS credentials
├── .gitignore
└── README.md
```

---

## Component Specifications

### 1. Frontend (`frontend-ui`)
* **Framework:** Lightweight React using Vite.
* **Functionality:**
  * Header displaying `"Cloud Retail Internal Dashboard"`.
  * Card showing live data fetched from `/api/products` (retrieved from the backend).
  * Clear error states if the backend or database is unreachable.
* **NGINX Configuration (`nginx.conf`):**
  * Runs as an unprivileged user on port `8080`.
  * Serves compiled static assets from `/usr/share/nginx/html`.
  * Reverse proxy block forwarding `/api/` requests to the internal Kubernetes DNS name of the backend (`http://backend-api.backend.svc.cluster.local:8000/api/`). This avoids CORS issues and keeps the backend private.
* **Dockerfile:**
  * Stage 1: `node:20-alpine` runs `npm install` and `npm run build`.
  * Stage 2: `nginxinc/nginx-unprivileged:alpine` copies `/dist` output and runs rootless.

### 2. Backend (`backend-api`)
* **Framework:** Python FastAPI with `SQLAlchemy` and `psycopg2-binary`.
* **Endpoints:**
  * `GET /api/health`: Health probe endpoint.
  * `GET /api/products`: Queries PostgreSQL database table named `products` and returns catalog items (`id`, `name`, `description`, `price`, `stock`).
* **Database Auto-Seeding (CRITICAL):**
  * Uses `Base.metadata.create_all(bind=engine)` on startup to automatically create the table without requiring manual SQL migrations.
  * Immediately checks if the table is empty. If empty, automatically inserts 3 dummy retail products:
    1. **Mechanical Keyboard** ($129.99, Stock: 45)
    2. **Wireless Mouse** ($49.99, Stock: 120)
    3. **USB-C Hub** ($34.50, Stock: 80)
* **Configuration:**
  * Reads DB host, user, password, and name from environment variables (`DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`).
* **Dockerfile:**
  * Multi-stage build using `python:3.11-slim`.
  * Runs as non-root user `appuser` (`UID 10001`).
  * No development dependencies in final image.

---

## Student Step-by-Step Integration Guide

### Step 1: Zero-Code Container Packaging

You do not need Node.js, npm, or Python installed on your local machine. Both applications use Docker multi-stage builds.

1. **Clone the application repo:**
   ```bash
   git clone https://github.com/alamz-tech/cloud-retail-microservices.git
   cd cloud-retail-microservices
   ```

2. **Build and tag the containers locally:**
   ```bash
   # Set your AWS environment variables
   export AWS_REGION="us-east-1"
   export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

   # Authenticate Docker to Amazon ECR
   aws ecr get-login-password --region ${AWS_REGION} | \
     docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

   # Build the frontend (compiles React and packages into NGINX rootless)
   docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-frontend:v1 ./frontend-ui

   # Build the backend (packages FastAPI in non-root Python runtime)
   docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-backend:v1 ./backend-api
   ```

3. **Push images to your private ECR repositories:**
   ```bash
   docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-frontend:v1
   docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-backend:v1
   ```

### Step 2: Infrastructure Provisioning (Terraform)

Navigate to your personal infrastructure repository and execute your Terraform code to provision:
* Custom VPC with dedicated public and private subnets.
* Amazon RDS PostgreSQL instance (`db.t4g.micro`) placed in private database subnets.
* AWS Secrets Manager secret (`retail-app/rds/credentials`) storing the database connection string and credentials.
* Amazon EKS cluster with OIDC provider enabled for IAM Roles for Service Accounts (IRSA).

### Step 3: Secrets Integration with ESO

1. Deploy the External Secrets Operator:
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm repo update
   helm install external-secrets external-secrets/external-secrets \
     -n external-secrets \
     --create-namespace \
     --set installCRDs=true
   ```

2. Create the backend namespace and apply the `ExternalSecret`:
   ```bash
   kubectl apply -f backend-api/k8s/namespace.yaml
   kubectl apply -f backend-api/k8s/external-secret.yaml
   ```

3. Verify secret synchronization:
   ```bash
   kubectl get externalsecrets -n backend
   # Must show STATUS: SecretSynced
   kubectl get secret rds-credentials -n backend
   ```

### Step 4: Deploy Backend Service & Ingress

1. Update the image in `backend-api/k8s/deployment.yaml` with your ECR image URI and deploy:
   ```bash
   kubectl apply -f backend-api/k8s/deployment.yaml
   kubectl apply -f backend-api/k8s/service.yaml
   ```

2. Verify auto-seeding in backend logs:
   ```bash
   kubectl get pods -n backend
   kubectl logs -n backend -l app=backend-api --tail=30
   ```

3. Update the image in `frontend-ui/k8s/deployment.yaml` with your ECR image URI and deploy:
   ```bash
   kubectl apply -f frontend-ui/k8s/namespace.yaml
   kubectl apply -f frontend-ui/k8s/deployment.yaml
   kubectl apply -f frontend-ui/k8s/service.yaml
   kubectl apply -f frontend-ui/k8s/ingress.yaml
   ```

4. Retrieve the public Application Load Balancer address:
   ```bash
   kubectl get ingress -n frontend
   ```

### Step 5: Network Isolation & Security Hardening

Apply the network policy to ensure all incoming traffic to the backend is dropped except connections originating from pods in the `frontend` namespace:

```bash
kubectl apply -f backend-api/k8s/network-policy.yaml
```

Verify isolation:
```bash
# Blocked from default namespace:
kubectl run curl-test --image=curlimages/curl -n default -i --tty --rm -- \
  curl -m 4 http://backend-api.backend.svc.cluster.local:8000/api/health

# Allowed from frontend namespace:
kubectl exec -n frontend -it $(kubectl get pods -n frontend -l app=frontend-ui -o jsonpath='{.items[0].metadata.name}') -- \
  wget -qO- http://backend-api.backend.svc.cluster.local:8000/api/health
```

---

## FinOps & Credit Protection Rules

* **The Spin-and-Kill Routine:** Run `terraform apply` when you begin working, test your configuration, and run `terraform destroy` when done for the day.
* **Spot Instances via Karpenter:** Worker nodes must run on EC2 Spot instances (`t3.small` / `t3.medium`). Verify with:
  ```bash
  kubectl get nodes -L karpenter.sh/capacity-type
  ```
* **Database Sizing:** Provision RDS PostgreSQL as `db.t4g.micro` with 20GB storage.
