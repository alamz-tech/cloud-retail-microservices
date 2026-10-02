# 1. DB Subnet Group
resource "aws_db_subnet_group" "rds" {
  name        = "${var.cluster_name}-db-subnet-group"
  description = "Database subnet group for retail PostgreSQL database"
  subnet_ids  = aws_subnet.database[*].id

  tags = {
    Name = "${var.cluster_name}-db-subnet-group"
  }
}

# 2. Database Security Group
resource "aws_security_group" "rds" {
  name        = "${var.cluster_name}-rds-sg"
  description = "Control traffic to Amazon RDS PostgreSQL"
  vpc_id      = aws_vpc.main.id

  # Allow inbound TCP port 5432 from both Karpenter nodes and EKS cluster/bootstrap nodes
  ingress {
    description = "Allow PostgreSQL access from EKS worker and cluster nodes"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [
      aws_security_group.nodes.id,
      aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-rds-sg"
  }
}

# 3. Random Secure Password for Database
resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# 4. Amazon RDS PostgreSQL Instance
resource "aws_db_instance" "main" {
  identifier             = "${var.cluster_name}-db"
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = var.db_instance_class
  allocated_storage      = var.db_allocated_storage
  storage_type           = "gp3"
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Hardened isolation
  publicly_accessible = false
  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "${var.cluster_name}-postgres"
  }
}
