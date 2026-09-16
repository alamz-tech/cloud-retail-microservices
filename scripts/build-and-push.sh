#!/usr/bin/env bash
set -euo pipefail

# Configuration
AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")}"

if [ -z "$AWS_ACCOUNT_ID" ]; then
  echo "[-] ERROR: Unable to determine AWS_ACCOUNT_ID. Please authenticate AWS CLI or export AWS_ACCOUNT_ID."
  exit 1
fi

ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
FRONTEND_IMAGE="${ECR_REGISTRY}/retail-frontend:v1"
BACKEND_IMAGE="${ECR_REGISTRY}/retail-backend:v1"

echo "[+] Authenticating Docker to Amazon ECR (${ECR_REGISTRY})..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

echo "[+] Ensuring ECR repositories exist..."
aws ecr describe-repositories --repository-names retail-frontend --region "${AWS_REGION}" >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name retail-frontend --region "${AWS_REGION}"

aws ecr describe-repositories --repository-names retail-backend --region "${AWS_REGION}" >/dev/null 2>&1 || \
  aws ecr create-repository --repository-name retail-backend --region "${AWS_REGION}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[+] Building multi-stage frontend container: ${FRONTEND_IMAGE}"
docker build -t "${FRONTEND_IMAGE}" "${ROOT_DIR}/frontend-ui"

echo "[+] Pushing frontend container to ECR..."
docker push "${FRONTEND_IMAGE}"

echo "[+] Building multi-stage backend container: ${BACKEND_IMAGE}"
docker build -t "${BACKEND_IMAGE}" "${ROOT_DIR}/backend-api"

echo "[+] Pushing backend container to ECR..."
docker push "${BACKEND_IMAGE}"

echo "[✓] Container build and push completed successfully!"
echo "    Frontend: ${FRONTEND_IMAGE}"
echo "    Backend:  ${BACKEND_IMAGE}"
