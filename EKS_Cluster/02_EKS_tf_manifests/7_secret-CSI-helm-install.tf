# Install Secrets Store CSI Driver (Kubernetes SIGs)
# gắn các "bí mật" (như mật khẩu Database, API Key, Token) từ các hệ thống bảo mật bên ngoài
# (như AWS Secrets Manager hoặc Parameter Store)
# thẳng vào bên trong Pod dưới dạng một thư mục chứa file hoặc biến môi trường một cách an toàn.
resource "helm_release" "secrets_store_csi_driver" {
  depends_on = [
    aws_eks_addon.podidentity,
    aws_eks_node_group.private_nodes
  ]

  name       = "csi-secrets-store"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"

  # Note: tokenRequests is required for EKS Pod Identity authentication when
  # the CSI driver is installed separately (not bundled via the AWS provider chart).
  # Audience "pods.eks.amazonaws.com" is for EKS Pod Identity. We do not configure
  # the IRSA audience (sts.amazonaws.com) because this course uses Pod Identity only.
  set = [
    {
      name  = "syncSecret.enabled"
      value = "true"
      # Khi driver này lấy được thông tin mật khẩu (ví dụ: chuỗi kết nối Database) 
      # từ AWS Secrets Manager về cụm, nó sẽ tự động tạo ra một Kubernetes Secret thông thường bên trong namespace của ứng dụng. 
      # Nhờ đó, các file cấu hình ứng dụng (Deployment) của bạn có thể đọc mật khẩu này dưới dạng biến môi trường (env) hoặc file một cách dễ dàng như các secret truyền thống khác.
    },
    {
      name  = "tokenRequests[0].audience"
      value = "pods.eks.amazonaws.com"
      # Khi trình điều khiển CSI muốn gọi sang AWS để lấy mật khẩu, nó cần xuất trình một loại token định danh (JWT) do Kubernetes cấp.
    },
  ]

  # Wait until all pods are ready
  wait            = true
  timeout         = 600
  cleanup_on_fail = true
}

# Outputs

output "helm_secrets_store_csi_driver_metadata" {
  description = "Metadata for the Secrets Store CSI Driver Helm release"
  value       = helm_release.secrets_store_csi_driver.metadata
}

#------------------------------
# Install AWS Secrets and Configuration Provider (ASCP)

# Nó chịu trách nhiệm nhận yêu cầu từ CSI Driver, dịch nghĩa nó thành các lệnh gọi API thực tế 
# sang AWS Secrets Manager hoặc Parameter Store, Ví dụ như: lấy dữ liệu mật khẩu về rồi bàn giao cho CSI Driver mang vào Pod.
resource "helm_release" "aws_secrets_provider" {
  depends_on = [
    aws_eks_addon.podidentity,
    aws_eks_node_group.private_nodes,
    helm_release.secrets_store_csi_driver
  ]


  name       = "secrets-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"

  # Disable re-installation of CSI driver (already installed separately)
  set = [
    {
      name  = "secrets-store-csi-driver.install"
      value = "false"
    },
    # Add toleration
    {
      name  = "tolerations[0].operator"
      value = "Exists"
      # Cho phép các Pod của AWS Secrets Provider có thể "chen chân" chạy được trên mọi Worker Node của cụm,
      #  kể cả những node đang bị gắn các nhãn đặc biệt (taint) như các node hệ thống hoặc node chuyên dụng.
    }
  ]

  # Wait for all pods to become ready
  wait            = true
  timeout         = 600
  cleanup_on_fail = true
}

################################################################################
# Outputs
################################################################################

output "helm_aws_secrets_provider_metadata" {
  description = "Metadata for the AWS Secrets and Configuration Provider Helm release"
  value       = helm_release.aws_secrets_provider.metadata
}
