# Datasource: AWS Load Balancer Controller IAM Policy get from aws-load-balancer-controller/ GIT Repo (latest)
# Thực hiện một HTTP GET request đến đường dẫn URL trỏ thẳng tới file iam_policy.json trên nhánh main của dự án AWS Load Balancer Controller.
# Thay vì bạn phải copy/paste thủ công một đoạn policy dài dằng dặc vào code Terraform, Terraform sẽ tự động "lên mạng" tải về nội dung JSON mới 
#nhất chứa danh sách các quyền hạn (ec2:DescribeSubnets, elasticloadbalancing:*, v.v.) mà controller này cần để có thể hoạt động.
data "http" "lbc_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"

  # Optional request headers
  request_headers = {
    Accept = "application/json"
  }
}

# LBC IAM Policy
/*
output "lbc_iam_policy" {
  value = data.http.lbc_iam_policy.response_body
}
*/

# AWS Load Balancer Controller là một thành phần cực kỳ quan trọng giúp cụm EKS của bạn tự động tạo và quản lý Application 
# Load Balancer (ALB) và Network Load Balancer (NLB) trên AWS khi bạn dùng các tài nguyên như Ingress hoặc Service loại LoadBalancer.

#----------------------------------------------------------------
# Resource: Create AWS Load Balancer Controller IAM Policy 
resource "aws_iam_policy" "lbc_iam_policy" {
  name        = "${local.name}-AWSLoadBalancerControllerIAMPolicy"
  path        = "/"
  description = "AWS Load Balancer Controller IAM Policy"
  policy      = data.http.lbc_iam_policy.response_body
}

output "lbc_iam_policy_arn" {
  value = aws_iam_policy.lbc_iam_policy.arn
}

# Resource: Create IAM Role 
resource "aws_iam_role" "lbc_iam_role" {
  name               = "${local.name}-lbc-iam-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name        = "${local.name}-lbc-iam-role"
    Environment = var.environment_name
    Component   = "AWS Load Balancer Controller"
  }
}

# Associate Load Balanacer Controller IAM Policy to  IAM Role
resource "aws_iam_role_policy_attachment" "lbc_iam_role_policy_attach" {
  policy_arn = aws_iam_policy.lbc_iam_policy.arn
  role       = aws_iam_role.lbc_iam_role.name
}

output "lbc_iam_role_arn" {
  description = "AWS Load Balancer Controller IAM Role ARN"
  value       = aws_iam_role.lbc_iam_role.arn
}

#-----------------------------------------------------------------
# EKS Pod Identity Association
resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = aws_eks_cluster.main.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc_iam_role.arn
}

# Output: LBC Pod Identity Association ARN
output "lbc_pod_identity_association_arn" {
  description = "AWS Load Balancer Controller Pod Identity Association ARN"
  value       = aws_eks_pod_identity_association.lbc.association_arn
}