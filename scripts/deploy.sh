#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${CLUSTER_NAME:-cloud-retail-eks}"

echo "======================================================================"
echo " Starting Capstone Platform Deployment: ${CLUSTER_NAME} (${AWS_REGION})"
echo "======================================================================"

# Step 1: Terraform Infrastructure Provisioning
echo "[+] Step 1: Provisioning Cloud Infrastructure via Terraform..."
cd "${ROOT_DIR}/infrastructure"
terraform init
terraform apply -auto-approve

# Step 2: Update Local Kubeconfig
echo "[+] Step 2: Updating kubeconfig for EKS cluster '${CLUSTER_NAME}'..."
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${AWS_REGION}"

# Step 3: Wait for Core Controllers
echo "[+] Step 3: Waiting for controllers (Karpenter, ESO, ALB Controller) to become ready..."
kubectl rollout status deployment/karpenter -n karpenter --timeout=180s || true
kubectl rollout status deployment/external-secrets -n external-secrets --timeout=180s || true
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=180s || true

# Step 4: Apply Karpenter CRDs (NodePool & EC2NodeClass)
echo "[+] Step 4: Applying Karpenter Spot NodePool and EC2NodeClass..."
kubectl apply -f "${ROOT_DIR}/manifests/karpenter/ec2nodeclass.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/karpenter/nodepool.yaml"

# Step 5: Configure External Secrets Operator ClusterSecretStore
echo "[+] Step 5: Applying External Secrets Operator ClusterSecretStore..."
kubectl apply -f "${ROOT_DIR}/manifests/eso/cluster-secret-store.yaml"

# Step 6: Deploy Backend Microservice
echo "[+] Step 6: Deploying Backend Namespace, ExternalSecret, Deployment, Service, and NetworkPolicy..."
kubectl apply -f "${ROOT_DIR}/manifests/backend/namespace.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/backend/external-secret.yaml"

echo "    Waiting for secret synchronization from AWS Secrets Manager..."
sleep 5
kubectl get externalsecrets -n backend

kubectl apply -f "${ROOT_DIR}/manifests/backend/deployment.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/backend/service.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/backend/network-policy.yaml"

# Step 7: Deploy Frontend Microservice & ALB Ingress
echo "[+] Step 7: Deploying Frontend Namespace, Deployment, Service, and Ingress..."
kubectl apply -f "${ROOT_DIR}/manifests/frontend/namespace.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/frontend/deployment.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/frontend/service.yaml"
kubectl apply -f "${ROOT_DIR}/manifests/frontend/ingress.yaml"

# Step 8: Status Summary
echo "======================================================================"
echo "[✓] Deployment completed! Checking cluster resources:"
echo "======================================================================"
kubectl get nodes -L karpenter.sh/capacity-type
kubectl get pods -A
kubectl get ingress -n frontend

echo ""
echo "To verify the complete platform deployment, run: ./scripts/verify.sh"
