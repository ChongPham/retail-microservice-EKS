# ====================
# IAM POLICIES FOR AMG
# ====================

# Policy 1: Amazon Grafana Prometheus Access Policy
resource "aws_iam_policy" "amg_prometheus_policy" {
  name        = "${local.cluster_name}-amg-prometheus-policy"
  description = "IAM policy for Grafana to access Amazon Managed Prometheus"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aps:ListWorkspaces",
          "aps:DescribeWorkspace",
          "aps:QueryMetrics",
          "aps:GetLabels",
          "aps:GetSeries",
          "aps:GetMetricMetadata"
        ]
        Resource = "*"
      }
    ]
  })
  tags = var.tags
}

# Policy 2: Amazon Grafana SNS Policy
resource "aws_iam_policy" "amg_sns_policy" {
  name        = "${local.cluster_name}-amg-sns-policy"
  description = "IAM policy for Grafana to publish AWS SNS notifications"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          "arn:aws:sns:*:${local.account_id}:grafana*"
        ]
      }
    ]
  })
  tags = var.tags
}

# Policy 3: AWS X-Ray Read Only Access (AWS Managed Policy - reference only)
data "aws_iam_policy" "xray_readonly" {
  arn = "arn:aws:iam::aws:policy/AWSXrayReadOnlyAccess"
}

# IAM ROLE FOR AMG
resource "aws_iam_role" "amg_iam_role" {
  name               = "${local.cluster_name}-amg-service-role"
  description        = "IAM role for Amazon Managed Grafana"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "grafana.amazonaws.com"
        }
      },
    ]
  })
  tags = var.tags
}

# Attach Policy 1: Prometheus Access
resource "aws_iam_role_policy_attachment" "amg_prometheus_policy_attachment" {
  role       = aws_iam_role.amg_iam_role.name
  policy_arn = aws_iam_policy.amg_prometheus_policy.arn
}

# Attach Policy 2: SNS Access
resource "aws_iam_role_policy_attachment" "amg_sns_policy_attachment" {
  role       = aws_iam_role.amg_iam_role.name
  policy_arn = aws_iam_policy.amg_sns_policy.arn
}

# Attach Policy 3: X-Ray Read Only (AWS Managed)
resource "aws_iam_role_policy_attachment" "amg_xray_readonly_attachment" {
  role       = aws_iam_role.amg_iam_role.name
  policy_arn = data.aws_iam_policy.xray_readonly.arn
}

# IAM Role
output "amg_iam_role_arn" {
  description = "ARN of the AMG IAM role"
  value       = aws_iam_role.amg_iam_role.arn
}

output "amg_iam_role_name" {
  description = "Name of the AMG service role"
  value       = aws_iam_role.amg_iam_role.name
}