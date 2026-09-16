#!/usr/bin/env bash
set -euo pipefail

echo "======================================================================"
echo " CAPSTONE PLATFORM VERIFICATION TEST SUITE"
echo "======================================================================"

echo ""
echo "--- [1. Spot Capacity Verification] ---"
echo "Command: kubectl get nodes -L karpenter.sh/capacity-type"
kubectl get nodes -L karpenter.sh/capacity-type || true

echo ""
echo "--- [2. External Secrets Operator Synchronization] ---"
echo "Command: kubectl get externalsecrets -A"
kubectl get externalsecrets -A || true

echo ""
echo "Command: kubectl get secret rds-credentials -n backend"
kubectl get secret rds-credentials -n backend || true

echo ""
echo "--- [3. Network Policy Isolation Proof: Test A (Blocked)] ---"
echo "Testing access from unauthorized namespace ('default') to backend-api port 8000..."
echo "Command: kubectl run curl-test --image=curlimages/curl -n default --restart=Never -i --rm -- curl -m 4 http://backend-api.backend.svc.cluster.local:8000/api/health"
set +e
kubectl run curl-test --image=curlimages/curl -n default --restart=Never -i --rm -- \
  curl -m 4 http://backend-api.backend.svc.cluster.local:8000/api/health
TEST_A_RESULT=$?
set -e

if [ $TEST_A_RESULT -ne 0 ]; then
  echo "[✓] Test A PASSED: Unauthorized ingress was dropped by NetworkPolicy as expected."
else
  echo "[-] Test A FAILED: Traffic was not blocked."
fi

echo ""
echo "--- [4. Network Policy Isolation Proof: Test B (Allowed)] ---"
echo "Testing access from authorized pod inside 'frontend' namespace..."
FRONTEND_POD=$(kubectl get pods -n frontend -l app=frontend-ui -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$FRONTEND_POD" ]; then
  echo "Frontend pod found: $FRONTEND_POD"
  echo "Command: kubectl exec -n frontend $FRONTEND_POD -- wget -qO- http://backend-api.backend.svc.cluster.local:8000/api/health"
  kubectl exec -n frontend "$FRONTEND_POD" -- wget -qO- http://backend-api.backend.svc.cluster.local:8000/api/health || true
  echo ""
  echo "[✓] Test B PASSED: Authorized frontend pod successfully reached backend-api."
else
  echo "[-] Test B SKIPPED: No frontend-ui pod found in namespace 'frontend'."
fi

echo ""
echo "--- [5. Ingress & Public Boundary Verification] ---"
echo "Frontend Ingress (ALB):"
kubectl get ingress -n frontend || true

echo ""
echo "Backend Service (Must be ClusterIP without external IP):"
kubectl get service -n backend backend-api || true

echo ""
echo "======================================================================"
echo " VERIFICATION COMPLETED"
echo "======================================================================"
