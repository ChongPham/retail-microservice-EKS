# Datasource: To get default EKS addon version compatible with EKS cluster version
data "aws_eks_addon_version" "prometheus_node_exporter_default" {
  addon_name         = "prometheus-node-exporter"
  kubernetes_version = data.terraform_remote_state.eks.outputs.eks_cluster_version
}

# Datasource: To get latest EKS addon version compatible with EKS cluster version
data "aws_eks_addon_version" "prometheus_node_exporter_latest" {
  addon_name         = "prometheus-node-exporter"
  kubernetes_version = data.terraform_remote_state.eks.outputs.eks_cluster_version
  most_recent        = true
}

# Prometheus Node Exporter là một công cụ chuẩn của hệ sinh thái Prometheus, có nhiệm vụ thu thập
# các chỉ số về tài nguyên phần cứng và hệ điều hành của từng Worker Node (máy chủ ảo EC2) trong cụm EKS.
# Node Exporter đóng vai trò là "người đo đạc", đứng ở từng Node để gom các chỉ số về CPU/RAM của máy chủ.
# Dùng khi cần đo đạc về chỉ số phần cứng của Node, ví dụ: CPU usage, Memory usage, Disk I/O, Network I/O, Load Average, và các thông số hệ thống khác.
# EKS Add-on: Prometheus Node Exporter 
resource "aws_eks_addon" "prometheus_node_exporter" {
  cluster_name  = data.terraform_remote_state.eks.outputs.eks_cluster_id
  addon_name    = "prometheus-node-exporter"
  addon_version = data.aws_eks_addon_version.prometheus_node_exporter_latest.version  
  # Conflict resolution
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  tags = var.tags
}


# Outputs
output "prometheus_node_exporter_addon_id" {
  description = "Prometheus Node Exporter EKS Addon ID"
  value       = aws_eks_addon.prometheus_node_exporter.id
}

output "prometheus_node_exporter_addon_version" {
  description = "Prometheus Node Exporter EKS Addon Version"
  value       = aws_eks_addon.prometheus_node_exporter.addon_version
}