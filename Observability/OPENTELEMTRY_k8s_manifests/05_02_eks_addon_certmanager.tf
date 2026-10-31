# Datasource: To get default EKS addon version compatible with EKS cluster version
data "aws_eks_addon_version" "cert_manager_default" {
  addon_name         = "cert-manager"
  kubernetes_version = data.terraform_remote_state.eks.outputs.eks_cluster_version
}

# Datasource: To get latest EKS addon version compatible with EKS cluster version
data "aws_eks_addon_version" "cert_manager_latest" {
  addon_name         = "cert-manager"
  kubernetes_version = data.terraform_remote_state.eks.outputs.eks_cluster_version
  most_recent        = true
}

# cert-manager EKS Addon (Prerequisite for ADOT)
resource "aws_eks_addon" "cert_manager" {
  cluster_name                = data.terraform_remote_state.eks.outputs.eks_cluster_id
  addon_name                  = "cert-manager"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  addon_version               = data.aws_eks_addon_version.cert_manager_latest.version
  tags = var.tags
}

# Khi bạn apply resource OpenTelemetryCollector, Kubernetes API Server gọi webhook của ADOT Operator để kiểm tra và bổ 
# sung cấu hình. Kết nối này sử dụng HTTPS, nên webhook cần chứng chỉ TLS mà API Server tin cậy. 
# Khi API Server gửi request HTTPS tới, ADOT Operator sẽ trình chứng chỉ này ra để chứng minh danh tính của nó, 
# đồng thời mã hóa toàn bộ đường truyền dữ liệu giữa Kubernetes API Server và Operator.
# Cert-manager đảm nhiệm việc cấp và gia hạn chứng chỉ theo cấu hình certificate của ADOT

# Bạn apply OpenTelemetryCollector
#   → Kubernetes API Server
#   → HTTPS → Webhook ADOT kiểm tra/bổ sung cấu hình
#               ↑
#        TLS certificate do cert-manager quản lý