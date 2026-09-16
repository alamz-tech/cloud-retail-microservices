#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "======================================================================"
echo " STARTING CLEAN CLOUD TEARDOWN (FinOps Credit Protection)"
echo "======================================================================"

echo "[+] Step 1: Deleting Kubernetes Ingress to trigger ALB removal..."
kubectl delete ingress retail-frontend-ingress -n frontend --ignore-not-found=true || true

echo "[+] Waiting 30 seconds for AWS Load Balancer Controller to release AWS ALB resources..."
sleep 30

echo "[+] Step 2: Deleting microservices namespaces..."
kubectl delete namespace frontend --ignore-not-found=true || true
kubectl delete namespace backend --ignore-not-found=true || true

echo "[+] Step 3: Deleting Karpenter NodePool and EC2NodeClass..."
kubectl delete nodepool spot-workers --ignore-not-found=true || true
kubectl delete ec2nodeclass default --ignore-not-found=true || true

echo "[+] Step 4: Running 'terraform destroy -auto-approve'..."
cd "${ROOT_DIR}/infrastructure"
terraform destroy -auto-approve

echo "======================================================================"
echo "[✓] Cloud teardown complete. Zero runaway cloud costs!"
echo "======================================================================"
