# ==============================================================================
# 1. Karpenter Controller (OCI Helm Chart - Optional via Terraform)
# ==============================================================================
resource "helm_release" "karpenter" {
  count            = var.install_helm_controllers ? 1 : 0
  namespace        = "karpenter"
  create_namespace = true
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.0.1"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller.arn
  }

  set {
    name  = "settings.clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "settings.interruptionQueue"
    value = aws_sqs_queue.karpenter_interruption.name
  }

  depends_on = [
    aws_eks_node_group.bootstrap,
    aws_iam_role_policy_attachment.karpenter_controller
  ]
}

# ==============================================================================
# 2. External Secrets Operator (ESO - Optional via Terraform)
# ==============================================================================
resource "helm_release" "external_secrets" {
  count            = var.install_helm_controllers ? 1 : 0
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "0.9.20"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_secrets.arn
  }

  depends_on = [
    aws_eks_node_group.bootstrap,
    aws_iam_role_policy_attachment.external_secrets
  ]
}

# ==============================================================================
# 3. AWS Load Balancer Controller (Optional via Terraform)
# ==============================================================================
resource "kubernetes_service_account" "aws_load_balancer_controller" {
  count = var.install_helm_controllers ? 1 : 0
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.load_balancer_controller.arn
    }
  }

  depends_on = [aws_eks_cluster.main]
}

resource "helm_release" "aws_load_balancer_controller" {
  count      = var.install_helm_controllers ? 1 : 0
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.8.1"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.aws_load_balancer_controller[0].metadata[0].name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = aws_vpc.main.id
  }

  depends_on = [
    aws_eks_node_group.bootstrap,
    kubernetes_service_account.aws_load_balancer_controller,
    aws_iam_role_policy_attachment.load_balancer_controller
  ]
}
