# EKS Access Management (thay thế hoặc bổ sung cho cơ chế file aws-auth ConfigMap cũ) 
# để quản lý việc xác thực và phân quyền truy cập vào cụm.
# vai trò như "sổ hộ khẩu" trung tâm trên AWS để quản lý xem những ai (User, Role, hoặc EC2 Node) 
# được phép chạm vào cụm EKS và được quyền làm gì ở mức độ hệ thống.
# "Hãy ghi nhận cái Role của Karpenter Node này vào danh sách được phép gia nhập cụm qua role arn"
resource "aws_eks_access_entry" "karpenter_node_access" {
  depends_on = [data.terraform_remote_state.eks]
  cluster_name  = data.terraform_remote_state.eks.outputs.eks_cluster_name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}