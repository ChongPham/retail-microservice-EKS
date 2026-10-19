# Datasource: To get default EKS addon version compatible with EKS cluster version
data "aws_eks_addon_version" "pia_default" {
  addon_name         = "eks-pod-identity-agent"
  kubernetes_version = aws_eks_cluster.main.version
}

# Datasource: To get latest EKS addon version compatible with EKS cluster version
data "aws_eks_addon_version" "pia_latest" {
  addon_name         = "eks-pod-identity-agent"
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

# EKS Addon: Pod Identity Agent
# Pod Identity Agent dùng để gắn quyền IAM trực tiếp cho các Pod ứng dụng chạy bên trong Kubernetes. Nhờ có agent này, 
# các ứng dụng của bạn trong cluster có thể gọi các dịch vụ AWS (như S3, DynamoDB, RDS,...) một cách bảo mật tuyệt đối mà không cần phải lưu trữ hay lộ AWS_ACCESS_KEY_ID ở bên trong code.
resource "aws_eks_addon" "podidentity" {
  depends_on   = [aws_eks_node_group.private_nodes]
  cluster_name = aws_eks_cluster.main.id
  addon_name   = "eks-pod-identity-agent"
  # Cấu hình này giúp Terraform tự động xử lý ghi đè nếu addon đã tồn tại sẵn hoặc xảy ra xung đột khi cập nhật phiên bản, 
  # tránh việc bị lỗi cú pháp dừng tiến trình.
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  # Use the latest EKS addon version compatible with the cluster's Kubernetes version
  addon_version = data.aws_eks_addon_version.pia_latest.version
}

# Outputs
output "pod_identity_agent_eksaddon_default_version" {
  value = data.aws_eks_addon_version.pia_default.version
}

output "pod_identity_agent_eksaddon_lastest_version" {
  value = data.aws_eks_addon_version.pia_latest.version
}
output "pod_identity_agent_eksaddon_arn" {
  value = aws_eks_addon.podidentity.arn
}

output "pod_identity_agent_eksaddon_id" {
  value = aws_eks_addon.podidentity.id
}