# Complete Step-by-Step Operator Runbook
## Secure 3-Tier Microservices Platform on Amazon EKS

This runbook guides you through executing every step individually in your terminal—giving you full visibility and hands-on insight into each Docker command, Terraform stage, Helm controller release, and kubectl resource.

*(Note: Automated helper scripts in `scripts/` are also provided as an optional shortcut).*

---

## Stage 0: Environment & Shell Preparation

Open your terminal and verify your active AWS identity and region:

```bash
# 1. Set environment variables
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# 2. Verify AWS identity
echo "Deploying as AWS Account: ${AWS_ACCOUNT_ID} in ${AWS_REGION}"

# 3. Ensure Docker Desktop is running
docker info >/dev/null 2>&1 && echo "Docker daemon is running!" || open -a Docker
```

---

## Stage 1: Zero-Code Container Packaging (Docker & ECR)

Both applications use multi-stage Dockerfiles. You do not need Python or Node.js installed locally.

### 1.1 Authenticate Docker to Amazon ECR
```bash
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
```

### 1.2 Create ECR Repositories (if not already created)
```bash
aws ecr create-repository --repository-name retail-frontend --region ${AWS_REGION} || true
aws ecr create-repository --repository-name retail-backend --region ${AWS_REGION} || true
```

### 1.3 Build and Push the Frontend UI Image
```bash
# Build (compiles Vite React SPA and packages into unprivileged rootless NGINX)
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-frontend:v1 ./frontend-ui

# Push to Amazon ECR
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-frontend:v1
```

### 1.4 Build and Push the Backend API Image
```bash
# Build (compiles dependencies and packages FastAPI into non-root UID 10001 runtime)
docker build -t ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-backend:v1 ./backend-api

# Push to Amazon ECR
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/retail-backend:v1
```

---

## Stage 2: Infrastructure Provisioning (Terraform)

### 2.1 Navigate to Infrastructure Directory and Initialize
```bash
cd infrastructure
terraform init
```

### 2.2 Run Terraform Plan
Inspect the resources that Terraform will create:
- Custom VPC, 3-tier subnets (Public, Private, Database), NAT Gateway, Internet Gateway
- EKS Cluster v1.30 with OIDC, VPC CNI Network Policy Agent, and Spot bootstrap node
- Amazon RDS PostgreSQL (`db.t4g.micro`, 20GB, private subnets)
- AWS Secrets Manager (`retail-app/rds/credentials`)
- IAM Roles for Service Accounts (IRSA for ESO, ALB Controller, Karpenter)
```bash
terraform plan
```

### 2.3 Apply Infrastructure Changes
```bash
terraform apply -auto-approve
```

### 2.4 Inspect Terraform Outputs
```bash
terraform output
```
Take note of:
- `cluster_name`: `cloud-retail-eks`
- `rds_address`: RDS PostgreSQL hostname
- `eso_role_arn`: IAM Role ARN for External Secrets Operator
- `alb_controller_role_arn`: IAM Role ARN for AWS Load Balancer Controller
- `karpenter_node_role_name`: IAM Role for Karpenter EC2 instances

Return to the repository root:
```bash
cd ..
```

---

## Stage 3: Connect `kubectl` to EKS Cluster

Update your local kubeconfig to authenticate with the new cluster:
```bash
aws eks update-kubeconfig --name cloud-retail-eks --region us-east-1

# Verify cluster connectivity
kubectl get nodes
```

---

## Stage 4: Deploy Platform Controllers via Helm CLI

### 4.1 Deploy External Secrets Operator (ESO)
```bash
# Add ESO Helm chart repo
helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets

# Retrieve the ESO IRSA role from Terraform
ESO_ROLE_ARN=$(terraform -chdir=infrastructure output -raw eso_role_arn)

# Install ESO with CRDs and IRSA annotation
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ESO_ROLE_ARN}"

# Wait for ESO pods to be Ready
kubectl rollout status deployment/external-secrets -n external-secrets
```

### 4.2 Deploy AWS Load Balancer Controller
```bash
# Add EKS charts repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

# Retrieve ALB Controller IRSA role and VPC ID
ALB_ROLE_ARN=$(terraform -chdir=infrastructure output -raw alb_controller_role_arn)
VPC_ID=$(aws eks describe-cluster --name cloud-retail-eks --region us-east-1 --query "cluster.resourcesVpcConfig.vpcId" --output text)

# Create the annotated ServiceAccount in kube-system
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${ALB_ROLE_ARN}
EOF

# Install the controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=cloud-retail-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1 \
  --set vpcId=${VPC_ID}

# Wait for ALB Controller to become Ready
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system
```

### 4.3 Deploy Karpenter Spot Autoscaler
```bash
# Retrieve Karpenter Controller Role ARN and SQS Queue Name
KARPENTER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/cloud-retail-eks-karpenter-controller-role"
QUEUE_NAME="cloud-retail-eks-karpenter"

# Install Karpenter via OCI Helm chart
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "1.0.1" \
  --namespace "karpenter" \
  --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${KARPENTER_ROLE_ARN}" \
  --set settings.clusterName=cloud-retail-eks \
  --set settings.interruptionQueue=${QUEUE_NAME}

# Wait for Karpenter pod to be Ready
kubectl rollout status deployment/karpenter -n karpenter

# Apply Karpenter Spot NodePool and EC2NodeClass
kubectl apply -f manifests/karpenter/ec2nodeclass.yaml
kubectl apply -f manifests/karpenter/nodepool.yaml
```

---

## Stage 5: Secrets Integration with External Secrets Operator

### 5.1 Apply ClusterSecretStore
This connects Kubernetes to AWS Secrets Manager using the ESO IAM role:
```bash
kubectl apply -f manifests/eso/cluster-secret-store.yaml
kubectl get clustersecretstore
```

### 5.2 Create Backend Namespace & Apply ExternalSecret
```bash
kubectl apply -f manifests/backend/namespace.yaml
kubectl apply -f manifests/backend/external-secret.yaml
```

### 5.3 Verify Secret Synchronization
```bash
# Check that ExternalSecret is synced
kubectl get externalsecrets -n backend
# EXPECTED: STATUS: SecretSynced, READY: True

# Check the generated native Kubernetes secret
kubectl get secret rds-credentials -n backend
# EXPECTED: rds-credentials contains DB_HOST, DB_USER, DB_PASSWORD, DB_NAME
```

---

## Stage 6: Workload Deployment (Backend & Frontend)

### 6.1 Deploy Backend API Microservice
```bash
# Deploy Service and Deployment
kubectl apply -f manifests/backend/deployment.yaml
kubectl apply -f manifests/backend/service.yaml

# Wait for Backend pods to be ready
kubectl rollout status deployment/backend-api -n backend

# Check Backend logs to verify DB connection and auto-seeding
kubectl logs -n backend -l app=backend-api --tail=30
```
> **Expected Output**: `"Successfully auto-seeded 3 initial retail products into the database."`

### 6.2 Deploy Frontend UI & AWS Application Load Balancer
```bash
# Deploy Frontend Namespace, Deployment, and Service
kubectl apply -f manifests/frontend/namespace.yaml
kubectl apply -f manifests/frontend/deployment.yaml
kubectl apply -f manifests/frontend/service.yaml

# Deploy ALB Ingress
kubectl apply -f manifests/frontend/ingress.yaml

# Wait for Frontend pods to be ready
kubectl rollout status deployment/frontend-ui -n frontend
```

### 6.3 Retrieve the Public Application Load Balancer URL
```bash
kubectl get ingress -n frontend retail-frontend-ingress
```
Copy the generated `ADDRESS` (e.g., `k8s-frontend-retailfr-xxxxxxxxxx.us-east-1.elb.amazonaws.com`).
Open it in your web browser. You will see the **Cloud Retail Internal Dashboard** displaying live products queried from Amazon RDS!

---

## Stage 7: Network Isolation & Security Hardening (NetworkPolicy)

### 7.1 Apply the Backend Network Policy
```bash
kubectl apply -f manifests/backend/network-policy.yaml
```

### 7.2 Run Test A (Blocked): Access from Unauthorized `default` Namespace
```bash
kubectl run curl-test --image=curlimages/curl -n default -i --tty --rm -- \
  curl -m 4 http://backend-api.backend.svc.cluster.local:8000/api/health
```
> **Expected Output:**
> `curl: (28) Connection timed out after 4001 milliseconds`
> (Proves the policy drops unauthorized ingress traffic).

### 7.3 Run Test B (Allowed): Access from Authorized `frontend` Pod
```bash
FRONTEND_POD=$(kubectl get pods -n frontend -l app=frontend-ui -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n frontend -it $FRONTEND_POD -- wget -qO- http://backend-api.backend.svc.cluster.local:8000/api/health
```
> **Expected Output:**
> `{"status":"healthy","database":"connected",...}`
> (Proves frontend-to-backend communication is authorized).

---

## Stage 8: Verify Public Boundaries & Spot Scaling

```bash
# 1. Spot Capacity Verification (Worker nodes on Spot)
kubectl get nodes -L karpenter.sh/capacity-type

# 2. Backend Service Boundary (Must be ClusterIP with no External IP)
kubectl get svc -n backend backend-api

# 3. RDS Public Boundary (Must be non-public)
aws rds describe-db-instances \
  --db-instance-identifier cloud-retail-eks-db \
  --query "DBInstances[0].PubliclyAccessible"
```

---

## Stage 9: Clean Cloud Teardown (FinOps Credit Protection)

When you are done testing, tear down all resources to protect your AWS credit pool:

```bash
# Step 1: Delete ALB Ingress first to allow AWS Load Balancer Controller to deprovision the ALB
kubectl delete ingress retail-frontend-ingress -n frontend
echo "Waiting 30 seconds for AWS ALB to delete..."
sleep 30

# Step 2: Delete Kubernetes namespaces
kubectl delete namespace frontend backend

# Step 3: Delete Karpenter CRDs & Helm releases
kubectl delete nodepool spot-workers || true
kubectl delete ec2nodeclass default || true
helm uninstall karpenter -n karpenter || true
helm uninstall aws-load-balancer-controller -n kube-system || true
helm uninstall external-secrets -n external-secrets || true

# Step 4: Destroy all AWS cloud infrastructure
cd infrastructure
terraform destroy -auto-approve
```
> **Expected Final Line:**
> `Destroy complete! Resources: 38 destroyed.`
