# Standard SNS topic for Grafana alert notifications.
# The AMG role receives sns:Publish on this exact ARN in 07_01.
resource "aws_sns_topic" "grafana_alerts" {
  name         = "grafana-${local.cluster_name}-alerts"
  display_name = "Grafana alerts"
  tags         = var.tags
}

# AWS sends a confirmation email when these subscriptions are created.
# Terraform cannot confirm the recipient's email on their behalf.
resource "aws_sns_topic_subscription" "grafana_alert_email" {
  for_each = var.grafana_alert_email_addresses

  topic_arn = aws_sns_topic.grafana_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

output "grafana_alert_topic_arn" {
  description = "SNS topic ARN to configure in the Grafana SNS contact point"
  value       = aws_sns_topic.grafana_alerts.arn
}

output "grafana_alert_region" {
  description = "AWS region for the Grafana SNS contact point"
  value       = var.aws_region
}
