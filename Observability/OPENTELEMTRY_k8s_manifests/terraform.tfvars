aws_region        = "us-east-1"
environment_name  = "dev"
business_division = "retail"

# Add real recipients before apply; each recipient must confirm the SNS email.
# Empty list creates the topic but no email subscriptions.
grafana_alert_email_addresses = []

tags = {
  Terraform   = "true"
  Environment = "dev"
  Project     = "OpenTelemetry"
  ManagedBy   = "platform-team"
}
