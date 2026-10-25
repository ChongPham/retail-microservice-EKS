data "aws_iam_policy_document" "adot_collector_assume" {
  statement {
    sid = "PodIdentity"
    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

# ADOT Collector IAM Role for Pod Identity
# IAM Role - ADOT Collector
resource "aws_iam_role" "adot_collector" {
  name = "${local.cluster_name}-adot-collector-role"
  assume_role_policy = data.aws_iam_policy_document.adot_collector_assume.json
}

# ADOT Collector IAM Policy
# Policy này được thiết kế riêng cho ADOT Collector (AWS Distro for OpenTelemetry) chạy trong cụm EKS
# Vai trò của ADOT Collector là "hút" các dữ liệu giám sát (telemetry data) gồm Logs (Nhật ký), 
# Metrics (Chỉ số đo lường), và Traces (Luồng vết) từ các ứng dụng rồi đẩy lên các dịch vụ quản lý của AWS.
resource "aws_iam_policy" "adot_collector" {
  name        = "${local.name}-adot-collector-policy"
  description = "IAM policy for ADOT collector to send telemetry to CloudWatch and X-Ray"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs Permissions (Write)
      {
        # Cho phép tạo Log Group, Log Stream và đẩy các sự kiện log (PutLogEvents, GetLogEvents, FilterLogEvents) lên hệ thống của CloudWatch.
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/*",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/*:*"
        ]
      },
      # CloudWatch Logs Permissions (Read - for querying/debugging)
      {
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/*",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/*:*"
        ]
      },
      # CloudWatch Metrics Permissions
      # Cho phép ADOT Collector gửi các chỉ số hiệu năng (như CPU, Memory, custom metrics của ứng dụng)
      #      về cho CloudWatch Metrics để vẽ biểu đồ và tạo cảnh báo (Alarms).
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      },
      # X-Ray Permissions
      # Khi ứng dụng của bạn tích hợp OpenTelemetry để trace các request đi qua nhiều microservice, 
      #     ADOT Collector sẽ nhận dữ liệu đó và đẩy lên AWS X-Ray để bạn trực quan hóa bản đồ gọi API (Service Map) 
      #     và tìm điểm nghẽn (bottleneck).
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries"
        ]
        Resource = "*"
      },
      # Amazon Managed Prometheus permissions   
      # Cho phép ADOT Collector đóng vai trò là trạm trung chuyển gom các metrics dạng Prometheus (Prometheus metrics scraping) 
      #     rồi bắn (RemoteWrite) trực tiếp vào không gian làm việc của Amazon Managed Service for Prometheus (AMP) để quản lý lâu dài. 
      {
        Effect = "Allow"
        Action = [
          "aps:RemoteWrite",
          "aps:QueryMetrics",
          "aps:GetSeries",
          "aps:GetLabels",
          "aps:GetMetricMetadata"
        ]
        Resource = aws_prometheus_workspace.amp.arn
      }      
    ]
  })

  tags = var.tags
}

# Attach IAM Policy to IAM Role
resource "aws_iam_role_policy_attachment" "adot_collector" {
  policy_arn = aws_iam_policy.adot_collector.arn
  role       = aws_iam_role.adot_collector.name
}

# ADOT Collector Pod Identity Association
resource "aws_eks_pod_identity_association" "adot_collector" {
  cluster_name    = data.terraform_remote_state.eks.outputs.eks_cluster_name
  namespace       = "default"
  service_account = "adot-collector"
  role_arn        = aws_iam_role.adot_collector.arn
  tags = var.tags
}

# Outputs
output "adot_collector_role_arn" {
  description = "IAM Role ARN for ADOT Collector"
  value       = aws_iam_role.adot_collector.arn
}