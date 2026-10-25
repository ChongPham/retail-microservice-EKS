# quyền dành cho các node (máy chủ EC2) mà Karpenter sẽ sinh ra (cấp phát) trong tương lai

data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_node" {
  name               = "${local.name}-karpenter-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "node_base_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy", # : Giúp máy chủ node kết nối và giao tiếp được với EKS Control Plane
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly", # Cho phép node tải các container image từ kho lưu trữ AWS ECR về để chạy.
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy", # Cho phép node quản lý địa chỉ IP và cấp phát mạng cho các Pod chạy bên trong nó (thông qua AWS VPC CNI).
    # AWS VPC CNI plugin (chạy ngầm như một DaemonSet trên node) sẽ gọi lệnh AWS API thông qua policy AmazonEKS_CNI_Policy để:
    #     Yêu cầu AWS gắn thêm các IP phụ vào card mạng của EC2 node.
    #     Lấy các IP đó cấp phát trực tiếp cho các Pod đang khởi tạo trên node.
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # Cho phép node truy cập vào các tính năng của AWS Systems Manager.
    # AWS SSM (Systems Manager) là công cụ quản lý máy chủ từ xa của Amazon
    # giúp Bạn có thể dùng AWS CLI hoặc Console bấm nút "Start Session" để mở một cửa sổ terminal dòng lệnh trực tiếp vào ruột con EC2 node đó một cách cực kỳ an toàn
    # sử dụng chọc vào node để debug, kiểm tra log, cài đặt phần mềm, v.v. mà không cần phải mở port SSH hay RDP ra ngoài Internet.
  ])

  role       = aws_iam_role.karpenter_node.name
  policy_arn = each.value
}

# outputs
output "karpenter_node_role_name" {
  description = "IAM Role Name used by EC2 nodes launched by Karpenter"
  value       = aws_iam_role.karpenter_node.name
}

output "karpenter_node_role_arn" {
  description = "IAM Role ARN used by EC2 nodes launched by Karpenter"
  value       = aws_iam_role.karpenter_node.arn
}

output "karpenter_node_role_unique_id" {
  description = "Unique ID for the Karpenter node IAM role"
  value       = aws_iam_role.karpenter_node.unique_id
}