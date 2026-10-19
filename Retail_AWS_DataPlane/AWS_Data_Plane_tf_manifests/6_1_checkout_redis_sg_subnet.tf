resource "aws_security_group" "redis_sg" {
  name        = "${local.name}-redis-sg"
  description = "Allow EKS cluster to access ElastiCache Redis"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    from_port                = 6379
    to_port                  = 6379
    protocol                 = "tcp"
    security_groups          = [data.terraform_remote_state.eks.outputs.eks_cluster_security_group_id]
    description              = "Allow traffic from EKS cluster SG"
  }
  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-redis-sg" }
}

# AWS Elastic Cache Subnet Group
resource "aws_elasticache_subnet_group" "redis_subnet_group" {
  name       = "${local.name}-redis-subnets"
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
}