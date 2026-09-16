# 1. AWS Secrets Manager Secret for RDS Database Credentials
resource "aws_secretsmanager_secret" "rds_credentials" {
  name                    = "retail-app/rds/credentials"
  description             = "PostgreSQL credentials for cloud retail microservices platform"
  recovery_window_in_days = 0

  tags = {
    Name = "retail-app-rds-credentials"
  }
}

# 2. Secret Version with JSON Payload
resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  secret_string = jsonencode({
    host     = aws_db_instance.main.address
    username = var.db_username
    password = random_password.db_password.result
    dbname   = var.db_name
  })
}
