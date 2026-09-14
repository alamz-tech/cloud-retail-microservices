# Cloud Retail Microservices Platform

[![Kubernetes](https://img.shields.io/badge/Kubernetes-EKS%201.29+-326CE5?logo=kubernetes&logoColor=white)](https://kubernetes.io/)
[![Docker](https://img.shields.io/badge/Docker-Multi--Stage-2496ED?logo=docker&logoColor=white)](https://www.docker.com/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.110+-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com/)
[![React](https://img.shields.io/badge/React-18-61DAFB?logo=react&logoColor=black)](https://react.dev/)
[![NGINX](https://img.shields.io/badge/NGINX-Unprivileged-009639?logo=nginx&logoColor=white)](https://nginx.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-RDS%2016-336791?logo=postgresql&logoColor=white)](https://aws.amazon.com/rds/)

A self-contained, production-grade 3-tier microservices workload designed for deployment on Amazon EKS.

The codebase is engineered so that **Docker handles 100% of compilation and dependency management** (multi-stage builds), and the backend microservice **automatically initialises its database schema and seeds initial retail catalog items on startup**.

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
│   ├── src/                     # React single-page UI (Vite)
│   │   ├── App.jsx              # Dashboard UI, metrics cards, catalog table, & error state
│   │   ├── main.jsx             # React DOM root mounting
│   │   └── index.css            # Clean responsive stylesheet (zero external CSS dependencies)
│   ├── index.html               # HTML entrypoint
│   ├── package.json             # NPM project definitions
│   ├── vite.config.js           # Vite configuration
│   ├── nginx.conf               # Hardened unprivileged NGINX with reverse proxy to backend
│   ├── Dockerfile               # Multi-stage build (Node 20 build -> NGINX Alpine)
│   └── k8s/
│       ├── namespace.yaml       # 'frontend' namespace manifest
│       ├── deployment.yaml      # Non-root deployment, dropped Linux capabilities
│       ├── service.yaml         # ClusterIP service (port 80 -> 8080)
│       └── ingress.yaml         # AWS ALB Ingress configuration
├── backend-api/
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py              # FastAPI service connecting to PostgreSQL
│   │   ├── database.py          # SQLAlchemy setup, connection retry, & auto-seeding
│   │   └── models.py            # SQLAlchemy models
│   ├── requirements.txt         # Production Python dependencies
│   ├── Dockerfile               # Multi-stage non-root Python build (UID 10001)
│   └── k8s/
│       ├── namespace.yaml       # 'backend' namespace manifest
│       ├── deployment.yaml      # Hardened deployment with ESO secret injection
│       ├── service.yaml         # Internal ClusterIP service (port 8000)
│       ├── external-secret.yaml # ESO Custom Resource to fetch RDS credentials
│       └── network-policy.yaml  # Network isolation: drops non-frontend traffic
├── .gitignore
└── README.md
```

---

## Component Specifications

### 1. Frontend (`frontend-ui`)
* **Framework:** Lightweight React using Vite.
* **Dashboard Features:**
  * Header displaying `"Cloud Retail Internal Dashboard"`.
  * Real-time metrics overview: Catalog Products, Units in Stock, Inventory Valuation, and Database Connection.
  * Live catalog card/table querying `/api/products` with item status tags (`In Stock`, `Low Stock`, `Out of Stock`).
  * Explicit, user-friendly error banners and connection diagnostics if the backend or database is unreachable.
* **NGINX Configuration (`nginx.conf`):**
  * Runs as an unprivileged user on port `8080`.
  * Serves compiled static assets from `/usr/share/nginx/html`.
  * Reverse proxy block forwarding `/api/` requests to the internal Kubernetes DNS name of the backend (`http://backend-api.backend.svc.cluster.local:8000/api/`). This avoids CORS issues and keeps the backend private.
  * Health probe endpoint at `/healthz` for ALB target group checks.
* **Dockerfile:**
  * Stage 1: `node:20-alpine` runs `npm install` and `npm run build`.
  * Stage 2: `nginxinc/nginx-unprivileged:alpine` copies `/dist` output and runs rootless.

### 2. Backend (`backend-api`)
* **Framework:** Python FastAPI with `SQLAlchemy` and `psycopg2-binary`.
* **Endpoints:**
  * `GET /api/health`: Health probe endpoint validating microservice and PostgreSQL database status.
  * `GET /api/products`: Queries the `products` table and returns catalog items (`id`, `name`, `description`, `price`, `stock`).
* **Database Auto-Seeding:**
  * Auto-executes `Base.metadata.create_all(bind=engine)` upon container startup.
  * Checks if the `products` table is empty (`count == 0`).
  * If empty, automatically inserts 3 initial retail items:
    1. **Mechanical Keyboard** ($129.99, Stock: 45)
    2. **Wireless Mouse** ($49.99, Stock: 120)
    3. **USB-C Hub** ($34.50, Stock: 80)
* **Configuration:**
  * Reads `DB_HOST`, `DB_USER`, `DB_PASSWORD`, and `DB_NAME` from environment variables (with URL-encoding for RDS password resilience).
* **Dockerfile:**
  * Multi-stage build on `python:3.11-slim`.
  * Runs as non-root user `appuser` (`UID 10001`, `GID 10001`).
  * Contains no compilers or build tools in final runtime image.

---

## Container Build & Packaging

Build and tag both container images using Docker:

```bash
# Build the frontend (compiles React and packages into NGINX rootless)
docker build -t <your-ecr-registry-uri>/retail-frontend:v1 ./frontend-ui

# Build the backend (packages FastAPI in non-root Python runtime)
docker build -t <your-ecr-registry-uri>/retail-backend:v1 ./backend-api
```

---

## Kubernetes Manifests Reference

### Backend (`backend-api/k8s/`)
| Manifest | Description |
| :--- | :--- |
| `namespace.yaml` | Declares the `backend` namespace. |
| `deployment.yaml` | Hardened deployment running under UID 10001 with dropped capabilities and credentials loaded from Secret `rds-credentials`. |
| `service.yaml` | Internal `ClusterIP` service exposing port `8000` (`backend-api.backend.svc.cluster.local`). |
| `external-secret.yaml` | External Secrets Operator resource targeting AWS Secrets Manager secret `retail-app/rds/credentials`. |
| `network-policy.yaml` | Restricts ingress to `backend-api` on port 8000 to only pods labeled with namespace `frontend`. |

### Frontend (`frontend-ui/k8s/`)
| Manifest | Description |
| :--- | :--- |
| `namespace.yaml` | Declares the `frontend` namespace. |
| `deployment.yaml` | Unprivileged deployment running under UID 101 on containerPort `8080` with dropped capabilities. |
| `service.yaml` | `ClusterIP` service exposing port `80` targeting port `8080`. |
| `ingress.yaml` | Ingress resource configured for the AWS Load Balancer Controller (`internet-facing` ALB, target-type `ip`). |
