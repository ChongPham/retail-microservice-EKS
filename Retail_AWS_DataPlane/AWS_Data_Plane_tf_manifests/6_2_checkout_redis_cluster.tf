# AWS Elastic Cache Redis Cluster
resource "aws_elasticache_cluster" "checkout_redis" {
  cluster_id           = "${local.name}-checkout-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis_subnet_group.name
  security_group_ids   = [aws_security_group.redis_sg.id]
  engine_version       = "7.1"
  parameter_group_name = "default.redis7"

  tags = { Name = "${local.name}-checkout-redis" }
}

# Outputs
output "checkout_redis_endpoint" {
  value = aws_elasticache_cluster.checkout_redis.cache_nodes[0].address
}

######
# Cấu hình HA thực sự với elastic cache replication group (primary + replica) và tự động failover sang vùng khác nếu node chính sập.
######
# resource "aws_elasticache_replication_group" "checkout_redis_ha" {
#   replication_group_id        = "${local.name}-checkout-redis-rep"
#   description                 = "Redis replication group for checkout with HA"
#   engine                      = "redis"
#   engine_version              = "7.1"
#   node_type                   = "cache.t3.micro"
#   port                        = 6379
#   subnet_group_name           = aws_elasticache_subnet_group.redis_subnet_group.name
#   security_group_ids          = [aws_security_group.redis_sg.id]
#   parameter_group_name        = "default.redis7"

#   # Cấu hình số lượng node (Ví dụ: 1 Primary và 1 Replica)
#   num_cache_clusters          = 2 
  
#   # Bật Multi-AZ để tự động Failover sang vùng khác nếu node chính sập
#   automatic_failover_enabled  = true 

#   tags = { Name = "${local.name}-checkout-redis-ha" }
# }

# output "checkout_redis_primary_endpoint" {
#   value = aws_elasticache_replication_group.checkout_redis_ha.primary_endpoint_address
# }

# output "checkout_redis_reader_endpoint" {
#   value = aws_elasticache_replication_group.checkout_redis_ha.reader_endpoint_address
# }