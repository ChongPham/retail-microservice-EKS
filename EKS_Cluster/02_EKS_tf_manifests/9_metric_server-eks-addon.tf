# Metrics Server là một thành phần cốt lõi, nhẹ (lightweight) chạy bên trong cụm Kubernetes,
# chuyên làm nhiệm vụ thu thập và tổng hợp dữ liệu tài nguyên (CPU và RAM) của các Node và Pod.
# Datasource: To get default EKS addon version compatible with EKS cluster version
data "aws_eks_addon_version" "metrics_server_default" {
  addon_name         = "metrics-server"
  kubernetes_version = aws_eks_cluster.main.version
}

variable "metrics_server_addon_version" {
  description = "Pinned Metrics Server EKS add-on version"
  type        = string
}

# Datasource: To get latest EKS addon version compatible with EKS cluster version
data "aws_eks_addon_version" "metrics_server_latest" {
  addon_name         = "metrics-server"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

# EKS Addon: Metrics Server
resource "aws_eks_addon" "metrics_server" {
  depends_on                  = [aws_eks_node_group.private_nodes]
  cluster_name                = aws_eks_cluster.main.id
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  # Use the latest EKS addon version compatible with the cluster's Kubernetes version
  addon_version = var.metrics_server_addon_version
}


# Outputs
output "metrics_server_eksaddon_default_version" {
  value = data.aws_eks_addon_version.metrics_server_default.version
}

output "metrics_server_eksaddon_lastest_version" {
  value = data.aws_eks_addon_version.metrics_server_latest.version
}

output "metrics_server_agent_eksaddon_arn" {
  value = aws_eks_addon.metrics_server.arn
}

output "metrics_server_agent_eksaddon_id" {
  value = aws_eks_addon.metrics_server.id
}