# Resource: Create IAM Role for EBS CSI Driver
# Amazon EBS CSI Driver (trình điều khiển giúp cụm EKS tạo và quản lý ổ cứng gắn ngoài EBS), nó cần 
#    phải dùng cơ chế Assume Role qua Pod Identity

# Bản chất của EBS CSI Driver là một thành phần 
# (chạy dưới dạng Pod trên các node) có nhiệm vụ nhận yêu cầu từ Kubernetes (như tạo PVC - PersistentVolumeClaim), 
# sau đó gọi trực tiếp vào API của AWS để thực hiện các thao tác:
#       Tạo ổ đĩa EBS mới (CreateVolume).
#       Gắn/tháo ổ đĩa vào máy chủ EC2 worker node (AttachVolume, DetachVolume).
#       Định dạng và xóa ổ đĩa (DeleteVolume).
resource "aws_iam_role" "ebs_csi_iam_role" {
  name               = "${local.name}-ebs-csi-iam-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name        = "${local.name}-ebs-csi-iam-role"
    Environment = var.environment_name
    Component   = "Amazon EBS CSI Driver"
  }
}

# Resource: Attach AWS Managed Policy for EBS CSI Driver
resource "aws_iam_role_policy_attachment" "ebs_csi_managed_policy_attach" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_iam_role.name
}

# Output: IAM Role ARN
output "ebs_csi_iam_role_arn" {
  description = "IAM Role ARN for Amazon EBS CSI Driver"
  value       = aws_iam_role.ebs_csi_iam_role.arn
}

# Resource: EKS Pod Identity Association for EBS CSI Driver
resource "aws_eks_pod_identity_association" "ebs_csi" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi_iam_role.arn
}

# Output: EBS CSI Pod Identity Association ARN
output "ebs_csi_pod_identity_association_arn" {
  description = "EBS CSI Driver Pod Identity Association ARN"
  value       = aws_eks_pod_identity_association.ebs_csi.association_arn
}