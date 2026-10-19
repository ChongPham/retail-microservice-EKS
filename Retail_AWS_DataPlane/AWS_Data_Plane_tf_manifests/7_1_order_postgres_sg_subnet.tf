# Security Group for RDS PostgreSQL
# Allow access only from EKS Cluster security group
resource "aws_security_group" "rds_postgresql_sg" {
  name        = "${local.name}-rds-postgresql-sg"
  description = "Allow RDS PostgreSQL access from EKS cluster"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description      = "Allow RDS PostgreSQL from EKS Cluster"
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    security_groups  = [data.terraform_remote_state.eks.outputs.eks_cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-rds-postgresql-sg"
  }
}

# RDS PostgreSQL Database Subnet Group for Orders Microservice
resource "aws_db_subnet_group" "rds_postgresql_subnet_group" {
  name       = "${local.name}-rds-postgresql-subnet-group"
  description = "Subnet group for Orders RDS PostgreSQL"
  subnet_ids  = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  tags = {
    Name = "${local.name}-rds-postgresql-subnet-group"
  }
}