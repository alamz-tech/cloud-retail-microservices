# Video Walkthrough Script (3 to 5 Minutes)
## Capstone Project: Secure 3-Tier Microservices Platform on Amazon EKS

This guide provides the exact timing, spoken narration, and screen actions required to record your 3-to-5 minute grading demonstration (Loom, YouTube Unlisted, or Google Drive).

---

## Video Run-of-Show & Scene Overview

| Timestamp | Section | Screen Focus | Key Talking Points |
| :--- | :--- | :--- | :--- |
| **0:00 - 0:45** | **Architecture & Node Health** | Terminal: `kubectl get nodes`, `kubectl get pods -A` | Introduce platform: EKS 1.30, Karpenter Spot scaling, non-root pods. |
| **0:45 - 1:30** | **External Secrets Operator** | Terminal: `kubectl get externalsecrets -A` | Zero plaintext secrets in Git, IRSA least-privilege, AWS Secrets Manager sync. |
| **1:30 - 2:30** | **Live Frontend & RDS Query** | Web Browser: Public ALB DNS | Live React dashboard, reverse proxy to private backend, auto-seeded catalog items. |
| **2:30 - 3:30** | **Network Policy Isolation** | Terminal: Blocked curl vs Allowed wget | Zero-trust isolation: VPC CNI drops unauthorized traffic; frontend namespace allowed. |
| **3:30 - 4:30** | **FinOps & Clean Teardown** | Terminal: `./scripts/teardown.sh` | Spin-and-kill routine, cost protection, `Destroy complete! Resources: 38 destroyed`. |

---

## Detailed Scene-by-Scene Script

### Scene 1: Introduction, Architecture, and Cluster Health (0:00 – 0:45)

**On-Screen Action:**
Open your terminal. Run:
```bash
kubectl get nodes -L karpenter.sh/capacity-type
kubectl get pods -A
```

**Spoken Narration:**
> "Hello everyone, my name is Hussein Alamutu, and today I'm presenting my capstone project: an enterprise-grade, cost-optimized 3-tier microservices platform running on Amazon EKS.
>
> In this terminal, you can see our cluster nodes. Notice the `CAPACITY-TYPE` label: our worker nodes are running on EC2 Spot instances provisioned dynamically by Karpenter, saving up to 90% in cloud computing costs.
>
> All system controllers and workload pods across `kube-system`, `karpenter`, `external-secrets`, `frontend`, and `backend` namespaces are running healthy. Both microservice pods run strictly under unprivileged, non-root security contexts with all Linux capabilities dropped."

---

### Scene 2: Secrets Management via External Secrets Operator (0:45 – 1:30)

**On-Screen Action:**
Run:
```bash
kubectl get externalsecrets -A
kubectl get secret rds-credentials -n backend
```

**Spoken Narration:**
> "Next, let's look at our secrets architecture. To adhere to zero-trust standards, zero database passwords or credentials exist in Git or our deployment manifests.
>
> Our Terraform infrastructure provisions an Amazon RDS PostgreSQL database and places its credentials as a structured JSON object into AWS Secrets Manager.
>
> Using IAM Roles for Service Accounts (IRSA) with fine-grained least privilege, the External Secrets Operator securely pulls those credentials and materializes them into a native Kubernetes Secret named `rds-credentials` in the `backend` namespace. The status shows `SecretSynced: True`."

---

### Scene 3: Live Application Access & Reverse Proxy Flow (1:30 – 2:30)

**On-Screen Action:**
1. In the terminal, show the Ingress resource:
```bash
kubectl get ingress -n frontend
```
2. Copy the ALB address, open Chrome/Safari, and paste the URL.
3. Show the "Cloud Retail Internal Dashboard" page with metrics cards and the 3 auto-seeded catalog items:
   - Mechanical Keyboard (\$129.99, Stock: 45)
   - Wireless Mouse (\$49.99, Stock: 120)
   - USB-C Hub (\$34.50, Stock: 80)

**Spoken Narration:**
> "Now let's examine traffic routing and ingress. We use the AWS Load Balancer Controller to provision an internet-facing Application Load Balancer targeting our frontend pods via IP target routing.
>
> Notice that the backend microservice has no public IP and is not directly exposed to the internet. Instead, our unprivileged NGINX frontend serves the React Single Page App and reverse-proxies `/api/` requests internally to `backend-api.backend.svc.cluster.local:8000`.
>
> Here in the browser, you can see the 'Cloud Retail Internal Dashboard'. It displays our catalog products, live inventory valuation, and confirms an active PostgreSQL database connection. These 3 initial products were automatically seeded into Amazon RDS on application container startup."

---

### Scene 4: Network Isolation & Zero-Trust NetworkPolicy (2:30 – 3:30)

**On-Screen Action:**
Return to the terminal. Run:
```bash
# Test A: Blocked access from default namespace
kubectl run curl-test --image=curlimages/curl -n default -i --tty --rm -- \
  curl -m 4 http://backend-api.backend.svc.cluster.local:8000/api/health
```
*(Wait 4 seconds for timeout: `curl: (28) Connection timed out`)*

Then run:
```bash
# Test B: Allowed access from frontend namespace
FRONTEND_POD=$(kubectl get pods -n frontend -l app=frontend-ui -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n frontend -it $FRONTEND_POD -- wget -qO- http://backend-api.backend.svc.cluster.local:8000/api/health
```

**Spoken Narration:**
> "To enforce defense-in-depth, we enabled the Amazon VPC CNI Network Policy Agent.
>
> Let's test network isolation. First, in Test A, I run a curl container from the unauthorized `default` namespace attempting to reach `backend-api` on port 8000. As you can see, after 4 seconds, the connection times out with error code 28. The packet is dropped immediately by our NetworkPolicy.
>
> Now in Test B, I execute a request from within an authorized pod in the `frontend` namespace. It returns a 200 OK JSON response with status 'healthy' and database 'connected'. This proves our network boundaries are strictly enforced."

---

### Scene 5: FinOps & Cloud Teardown Routine (3:30 – 4:30)

**On-Screen Action:**
Run:
```bash
./scripts/teardown.sh
```
*(Show the script deleting ingress, waiting for ALB release, and running `terraform destroy`)*

**Spoken Narration:**
> "Finally, as platform engineers operating in a modern cloud environment, cost protection and FinOps are critical.
>
> Under our 'Spin-and-Kill Routine', we never leave clusters or RDS instances running idle overnight. Here I run `./scripts/teardown.sh`.
>
> The script gracefully releases the AWS ALB, cleans up the workloads, and runs `terraform destroy -auto-approve`, completely decommissioning all 38 cloud resources.
>
> Thank you for watching my capstone project demonstration!"

---

## Recording Checklist for the Student

- [ ] Resolution: 1080p (1920x1080)
- [ ] Audio: Clear microphone with minimal background noise
- [ ] Browser window pre-opened side-by-side with your terminal
- [ ] Terminal font size enlarged (e.g. 14pt - 16pt) for easy grading readability
- [ ] Video duration: 3 to 5 minutes
- [ ] Upload: Unlisted YouTube, Loom, or shared Google Drive link (ensure permissions are set to "Anyone with the link can view")
