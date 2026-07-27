output "api_url" {
  value = "https://${var.domain_name}"
}

output "health_check_id" {
  value = aws_route53_health_check.primary.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.failover.arn
}
