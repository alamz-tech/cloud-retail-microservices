output "aws_region" {
  description = "AWS region deployed"
  value       = var.aws_region
}

output "cluster_name" {
  description = "Name of the provisioned EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS control plane API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_oidc_issuer_url" {
  description = "Cluster OIDC issuer URL for IRSA"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "rds_endpoint" {
  description = "Amazon RDS PostgreSQL connection endpoint (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "rds_address" {
  description = "Amazon RDS PostgreSQL address (host)"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "Amazon RDS PostgreSQL port"
  value       = aws_db_instance.main.port
}

output "secrets_manager_secret_name" {
  description = "AWS Secrets Manager Secret Name"
  value       = aws_secretsmanager_secret.rds_credentials.name
}

output "ecr_frontend_repository_url" {
  description = "ECR repository URL for retail-frontend"
  value       = data.aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_repository_url" {
  description = "ECR repository URL for retail-backend"
  value       = data.aws_ecr_repository.backend.repository_url
}

output "karpenter_node_role_name" {
  description = "IAM role name for Karpenter EC2 instances"
  value       = aws_iam_role.karpenter_node.name
}

output "karpenter_node_role_arn" {
  description = "IAM role ARN for Karpenter EC2 instances"
  value       = aws_iam_role.karpenter_node.arn
}

output "eso_role_arn" {
  description = "IAM role ARN for External Secrets Operator"
  value       = aws_iam_role.external_secrets.arn
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.load_balancer_controller.arn
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions CI/CD pipeline"
  value       = aws_iam_role.github_actions.arn
}
