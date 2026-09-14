# Cloud Retail Microservices Platform

[![Kubernetes](https://img.shields.io/badge/Kubernetes-EKS%201.29+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Docker](https://img.shields.io/badge/Docker-Multi--Stage-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.110+-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![React](https://img.shields.io/badge/React-18-61DAFB?logo=react&logoColor=black)](https://react.dev/)
[![NGINX](https://img.shields.io/badge/NGINX-Unprivileged-009639?logo=nginx&logoColor=white)](https://nginx.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-RDS%2016-336791?logo=postgresql&logoColor=white)](https://aws.amazon.com/rds/)

A production-grade, 3-tier microservices workload engineered for the **Amazon EKS DevOps/Platform Engineering Capstone Project**. 

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
│   ├── src/                     # React 18 single-page dashboard
│   │   ├── App.jsx              # Dashboard UI, metrics, catalog table, & error state
│   │   ├── main.jsx             # React DOM root mounting
│   │   └── index.css            # Modern responsive stylesheet (no external CSS dependencies)
│   ├── index.html               # Web page entrypoint
│   ├── package.json             # NPM project definitions
│   ├── vite.config.js           # Vite configuration with /api proxy
│   ├── nginx.conf               # Hardened unprivileged NGINX with internal reverse proxy
│   ├── Dockerfile               # Multi-stage build (Node 20 Alpine -> NGINX Unprivileged)
│   ├── .dockerignore
│   └── k8s/
│       ├── namespace.yaml       # 'frontend' namespace
│       ├── deployment.yaml      # Non-root deployment, dropped Linux capabilities
│       ├── service.yaml         # ClusterIP service (port 80 -> 8080)
│       └── ingress.yaml         # AWS Load Balancer Controller ALB Ingress
├── backend-api/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py              # FastAPI application with /api/health and /api/products
│   │   ├── database.py          # SQLAlchemy engine, connection retry, & auto-seeding
│   │   └── models.py            # SQLAlchemy Product model
│   ├── requirements.txt         # Production Python dependencies
│   ├── Dockerfile               # Multi-stage non-root build (UID 10001)
│   ├── .dockerignore
│   └── k8s/
│       ├── namespace.yaml       # 'backend' namespace
│       ├── deployment.yaml      # Hardened deployment with ESO secret injection
│       ├── service.yaml         # ClusterIP service (port 8000)
│       ├── external-secret.yaml # ExternalSecret resource syncing AWS Secrets Manager
│       └── network-policy.yaml  # Network isolation: drops non-frontend traffic
├── docker-compose.yml           # 1-command local sandbox with PostgreSQL 16
├── .gitignore
└── README.md
```

---

## Microservices Breakdown

### 1. Frontend UI (`frontend-ui`)
* **Framework:** React 18 bundled with Vite.
* **Dashboard Features:**
  * Displays header: `"Cloud Retail Internal Dashboard"`.
  * Real-time metrics overview: Catalog Products, Units in Stock, Inventory Valuation, and Database Connection.
  * Live catalog table querying `/api/products` with product status tags (`In Stock`, `Low Stock`, `Out of Stock`).
  * Explicit, user-friendly error banners and diagnostics if the backend or database is unreachable.
* **NGINX Reverse Proxy (`nginx.conf`):**
  * Runs completely unprivileged on port `8080`.
  * Reverse proxies `/api/` traffic directly to `http://backend-api.backend.svc.cluster.local:8000/api/`. This avoids browser CORS errors and prevents exposing the backend service to the internet.
  * Provides `/healthz` for ALB target group health checks.
* **Container Build:**
  * Stage 1: `node:20-alpine` runs `npm install` and compiles the bundle.
  * Stage 2: `nginxinc/nginx-unprivileged:alpine` serves static files and proxies API traffic.

### 2. Backend API (`backend-api`)
* **Framework:** FastAPI with SQLAlchemy and `psycopg2-binary`.
* **Endpoints:**
  * `GET /api/health`: Health probe endpoint validating PostgreSQL database connectivity.
  * `GET /api/products`: Queries the `products` table and returns catalog items (`id`, `name`, `description`, `price`, `stock`).
* **Automatic Database Initialization & Seeding:**
  * Automatically executes `Base.metadata.create_all(bind=engine)` upon container startup.
  * Automatically queries the `products` table. If 0 records exist, it inserts 3 dummy products:
    1. **Mechanical Keyboard** ($129.99, Stock: 45)
    2. **Wireless Mouse** ($49.99, Stock: 120)
    3. **USB-C Hub** ($34.50, Stock: 80)
* **Resilience:**
  * Includes connection retries with exponential backoff on startup so backend pods gracefully wait if RDS is still initializing.
* **Container Build:**
  * Multi-stage build based on `python:3.11-slim`.
  * Runs as dedicated unprivileged user `appuser` (`UID 10001`, `GID 10001`).
  * Contains no compilers or build tools in the final image.

---

## Quickstart: Local Validation with Docker Compose

You can validate the full 3-tier architecture locally before pushing to AWS:

```bash
# Clone the repository
git clone https://github.com/alamz-tech/cloud-retail-microservices.git
cd cloud-retail-microservices

# Start Postgres, Backend API, and Frontend UI
docker compose up --build
```

* **Frontend Dashboard:** Open [http://localhost:8080](http://localhost:8080)
* **Backend API Docs:** Open [http://localhost:8000/docs](http://localhost:8000/docs)
* **Backend Health Probe:** Open [http://localhost:8000/api/health](http://localhost:8000/api/health)

Press `Ctrl+C` and run `docker compose down -v` when finished.

---

## Step-by-Step EKS Capstone Deployment

### Step 1: Zero-Code Container Packaging (ECR)

Build and tag both containers locally using Docker:

```bash
# Set your AWS variables
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# Authenticate Docker to Amazon ECR
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create ECR repositories (if not already created by Terraform)
aws ecr create-repository --repository-name retail-frontend --region ${AWS_REGION} || true
aws ecr create-repository --repository-name retail-backend --region ${AWS_REGION} || true

# Build and push Frontend
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-frontend:v1 ./frontend-ui
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-frontend:v1

# Build and push Backend
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-backend:v1 ./backend-api
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-backend:v1
```

### Step 2: Infrastructure Provisioning (Terraform)

From your Terraform infrastructure repository, provision:
1. VPC with public and private subnets.
2. RDS PostgreSQL database (`db.t4g.micro`, 20 GB).
3. AWS Secrets Manager secret: `retail-app/rds/credentials` with keys:
   ```json
   {
     "host": "<rds-endpoint>",
     "username": "postgres",
     "password": "<secure-password>",
     "dbname": "retail_db",
     "port": "5432"
   }
   ```
4. EKS cluster with Karpenter (configured for Spot instances) and OIDC IRSA enabled.

### Step 3: Secrets Integration with ESO

1. Deploy External Secrets Operator via Helm:
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm repo update
   helm install external-secrets external-secrets/external-secrets \
     -n external-secrets \
     --create-namespace \
     --set installCRDs=true
   ```

2. Create the backend namespace:
   ```bash
   kubectl apply -f backend-api/k8s/namespace.yaml
   ```

3. Ensure your `ClusterSecretStore` (referencing your IRSA role for Secrets Manager) is configured, then apply the `ExternalSecret`:
   ```bash
   kubectl apply -f backend-api/k8s/external-secret.yaml
   ```

4. Verify secret synchronization:
   ```bash
   kubectl get externalsecret -n backend
   # Output must show STATUS: SecretSynced
   kubectl get secret rds-credentials -n backend
   ```

### Step 4: Deploying Backend & Network Isolation

1. Update the image in `backend-api/k8s/deployment.yaml` with your ECR image URI.
2. Apply the backend manifests:
   ```bash
   kubectl apply -f backend-api/k8s/deployment.yaml
   kubectl apply -f backend-api/k8s/service.yaml
   kubectl apply -f backend-api/k8s/network-policy.yaml
   ```

3. Verify the pods are running and auto-seeding completed:
   ```bash
   kubectl get pods -n backend
   kubectl logs -n backend -l app=backend-api --tail=50
   # You should see: "Successfully auto-seeded 3 initial retail products into the database."
   ```

### Step 5: Deploying Frontend & Ingress

1. Update the image in `frontend-ui/k8s/deployment.yaml` with your ECR image URI.
2. Apply the frontend manifests:
   ```bash
   kubectl apply -f frontend-ui/k8s/namespace.yaml
   kubectl apply -f frontend-ui/k8s/deployment.yaml
   kubectl apply -f frontend-ui/k8s/service.yaml
   kubectl apply -f frontend-ui/k8s/ingress.yaml
   ```

3. Obtain the Application Load Balancer address:
   ```bash
   kubectl get ingress -n frontend
   ```
   Open the `ADDRESS` in your browser. You will see the **Cloud Retail Internal Dashboard** displaying live product catalog data retrieved from your Amazon RDS database!

---

## Network Isolation Verification (Step 5 of Capstone)

Verify that the `allow-frontend-only` NetworkPolicy is enforcing strict isolation:

```bash
# 1. Spawn a test pod in the DEFAULT namespace (should be BLOCKED)
kubectl run curl-test --image=curlimages/curl -i --tty --rm -- \
  curl -m 3 http://backend-api.backend.svc.cluster.local:8000/api/health
# Expected: Connection timed out (Blocked by NetworkPolicy)

# 2. Test curl from a pod in the FRONTEND namespace (should SUCCEED)
kubectl exec -n frontend -it $(kubectl get pods -n frontend -l app=frontend-ui -o jsonpath='{.items[0].metadata.name}') -- \
  wget -qO- http://backend-api.backend.svc.cluster.local:8000/api/health
# Expected: {"status":"healthy","database":"connected",...}
```

---

## FinOps & Credit Protection Rules

* **The Spin-and-Kill Routine:** Run `terraform apply` when you begin your session. When finished, immediately run `terraform destroy` to prevent overnight charges.
* **Spot Instances with Karpenter:** Worker nodes must utilize Spot instances (`t3.small` / `t3.medium`). Verify with:
  ```bash
  kubectl get nodes -L karpenter.sh/capacity-type
  ```
* **Database Sizing:** Ensure RDS uses `db.t4g.micro` with 20GB storage.

---

## Capstone Submission Deliverables

1. **Deliverable 1: Source Code Repository (GitHub)**
   * Link to your repository containing `frontend-ui/`, `backend-api/`, and `infrastructure/`.
2. **Deliverable 2: Evidence Document (`EVIDENCE.md`)**
   * Spot Capacity Verification (`kubectl get nodes -L karpenter.sh/capacity-type`).
   * External Secrets Sync (`kubectl get externalsecrets -A`).
   * Network Isolation Proof (`curl` output from unauthorized vs frontend namespaces).
   * Clean Cloud Teardown output (`Destroy complete! Resources: X destroyed.`).
3. **Deliverable 3: Video Walkthrough (3-5 Minutes)**
   * Demonstrating healthy pods (`kubectl get pods -A`), opening the ALB URL in the browser, verifying network policy, and running `terraform destroy`.
