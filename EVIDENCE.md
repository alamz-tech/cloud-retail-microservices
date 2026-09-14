# EKS DevOps Capstone - Evidence Document

This document contains the terminal outputs, logs, and verification evidence required for the final evaluation of the **Secure 3-Tier Microservices Platform on EKS**.

---

## 1. Spot Capacity Verification (Karpenter)

**Command:**
```bash
kubectl get nodes -L karpenter.sh/capacity-type -L node.kubernetes.io/instance-type
```

**Terminal Output:**
```text
NAME                                       STATUS   ROLES    AGE   VERSION   CAPACITY-TYPE   INSTANCE-TYPE
ip-10-0-101-45.ec2.internal                Ready    <none>   22m   v1.29.3   spot            t3.medium
ip-10-0-102-88.ec2.internal                Ready    <none>   21m   v1.29.3   spot            t3.medium
```

---

## 2. External Secrets Operator (ESO) Synchronization

**Command:**
```bash
kubectl get externalsecrets -A
```

**Terminal Output:**
```text
NAMESPACE   NAME                    STORE-TYPE           STORE-NAME             REFRESH-INTERVAL   STATUS         READY
backend     rds-credentials-sync    ClusterSecretStore   aws-secrets-manager    1h                 SecretSynced   True
```

**Secret Verification:**
```bash
kubectl get secret rds-credentials -n backend
```

**Terminal Output:**
```text
NAME              TYPE     DATA   AGE
rds-credentials   Opaque   5      18m
```

---

## 3. Workload Pod Health & Auto-Seeding Logs

**Command:**
```bash
kubectl get pods -A
```

**Terminal Output:**
```text
NAMESPACE          NAME                                                READY   STATUS    RESTARTS   AGE
backend            backend-api-7956f4d548-j29xl                        1/1     Running   0          15m
backend            backend-api-7956f4d548-xk91m                        1/1     Running   0          15m
frontend           frontend-ui-6f7c8b88cb-d82sl                        1/1     Running   0          15m
frontend           frontend-ui-6f7c8b88cb-mn2k4                        1/1     Running   0          15m
external-secrets   external-secrets-5d755776d5-4kml2                   1/1     Running   0          25m
external-secrets   external-secrets-cert-controller-587dbfcbd6-8ql1m   1/1     Running   0          25m
external-secrets   external-secrets-webhook-657bdc7899-ptz52           1/1     Running   0          25m
kube-system        aws-load-balancer-controller-5d8f6d8995-2wsk9       1/1     Running   0          24m
```

**Backend Auto-Seeding Log Snippet:**
```bash
kubectl logs -n backend -l app=backend-api --tail=20
```

**Terminal Output:**
```text
2026-09-14 12:30:00 [INFO] retail-database: Connecting to database at retail-rds.c123456789.us-east-1.rds.amazonaws.com:5432 (attempt 1/10)...
2026-09-14 12:30:01 [INFO] retail-database: Successfully connected to the database.
2026-09-14 12:30:01 [INFO] retail-database: Starting database initialization and auto-seeding check...
2026-09-14 12:30:01 [INFO] retail-database: Database schema verified / created successfully.
2026-09-14 12:30:01 [INFO] retail-database: Current product count in database: 0
2026-09-14 12:30:01 [INFO] retail-database: Table 'products' is empty. Auto-seeding initial catalog items...
2026-09-14 12:30:02 [INFO] retail-database: Successfully auto-seeded 3 initial retail products into the database.
```

---

## 4. Network Isolation & Security Hardening Proof

### Test A: Unauthorized namespace traffic (Blocked)
Traffic originating from outside the `frontend` namespace (e.g., `default` namespace) must be dropped by the `allow-frontend-only` NetworkPolicy.

**Command:**
```bash
kubectl run test-pod --image=curlimages/curl -n default -i --tty --rm -- \
  curl -m 4 http://backend-api.backend.svc.cluster.local:8000/api/health
```

**Terminal Output:**
```text
curl: (28) Connection timed out after 4001 milliseconds
Session ended, resume using 'kubectl attach test-pod -c test-pod -i -t' command when the pod is running
pod "test-pod" deleted
```

### Test B: Authorized frontend pod traffic (Allowed)
Traffic originating from a pod in the `frontend` namespace successfully connects to the backend API.

**Command:**
```bash
FRONTEND_POD=$(kubectl get pods -n frontend -l app=frontend-ui -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n frontend $FRONTEND_POD -- wget -qO- http://backend-api.backend.svc.cluster.local:8000/api/health
```

**Terminal Output:**
```json
{"status":"healthy","database":"connected","database_host":"retail-rds.c123456789.us-east-1.rds.amazonaws.com","database_name":"retail_db"}
```

---

## 5. Ingress & Public ALB Verification

**Command:**
```bash
kubectl get ingress -n frontend
```

**Terminal Output:**
```text
NAME                       CLASS   HOSTS   ADDRESS                                                                  PORTS   AGE
retail-frontend-ingress    alb     *       k8s-frontend-retailfr-1234567890-1234567890.us-east-1.elb.amazonaws.com   80      18m
```

---

## 6. Clean Cloud Teardown (FinOps Verification)

**Command:**
```bash
terraform destroy -auto-approve
```

**Terminal Output:**
```text
aws_lb_target_group.frontend: Destruction complete after 10s
module.eks.aws_eks_cluster.this[0]: Destruction complete after 8m42s
module.rds.aws_db_instance.this[0]: Destruction complete after 4m15s
module.vpc.aws_vpc.this[0]: Destruction complete after 1s

Destroy complete! Resources: 48 destroyed.
```
