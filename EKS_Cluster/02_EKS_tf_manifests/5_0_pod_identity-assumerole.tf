# Datasource: IAM Policy Document 
# IAM Policy Document dùng để định nghĩa Trust Policy (Chính sách tin cậy) cho các IAM Role sử dụng tính năng EKS Pod Identity.
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}