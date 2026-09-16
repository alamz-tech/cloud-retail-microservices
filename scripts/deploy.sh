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

# Step 3: Install Core Controllers via Helm CLI
echo "[+] Step 3: Fetching IRSA roles and installing Controllers via Helm CLI..."
cd "${ROOT_DIR}/infrastructure"
ESO_ROLE_ARN=$(terraform output -raw eso_role_arn 2>/dev/null || echo "")
ALB_ROLE_ARN=$(terraform output -raw alb_controller_role_arn 2>/dev/null || echo "")
KARPENTER_NODE_ROLE=$(terraform output -raw karpenter_node_role_name 2>/dev/null || echo "")
VPC_ID=$(terraform state show aws_vpc.main | grep -E '^\s*id\s*=' | awk '{print $3}' | tr -d '"' 2>/dev/null || echo "")

# 3A. Install External Secrets Operator
echo "[+] Step 3A: Installing External Secrets Operator via Helm..."
helm repo add external-secrets https://charts.external-secrets.io || true
helm repo update external-secrets
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ESO_ROLE_ARN}"

# 3B. Install AWS Load Balancer Controller
echo "[+] Step 3B: Installing AWS Load Balancer Controller via Helm..."
helm repo add eks https://aws.github.io/eks-charts || true
helm repo update eks
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-load-balancer-controller
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: ${ALB_ROLE_ARN}
EOF
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="${AWS_REGION}" \
  --set vpcId="${VPC_ID}"

# 3C. Install Karpenter
echo "[+] Step 3C: Installing Karpenter via Helm..."
KARPENTER_ROLE_ARN=$(terraform state show aws_iam_role.karpenter_controller | grep -E '^\s*arn\s*=' | awk '{print $3}' | tr -d '"' 2>/dev/null || echo "")
QUEUE_NAME=$(terraform state show aws_sqs_queue.karpenter_interruption | grep -E '^\s*name\s*=' | awk '{print $3}' | tr -d '"' 2>/dev/null || echo "")
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "1.0.1" \
  --namespace "karpenter" \
  --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${KARPENTER_ROLE_ARN}" \
  --set settings.clusterName="${CLUSTER_NAME}" \
  --set settings.interruptionQueue="${QUEUE_NAME}"

echo "[+] Waiting for controllers to be ready..."
kubectl rollout status deployment/external-secrets -n external-secrets --timeout=180s || true
kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=180s || true
kubectl rollout status deployment/karpenter -n karpenter --timeout=180s || true
cd "${ROOT_DIR}"

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
