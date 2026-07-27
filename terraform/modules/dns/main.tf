# DNS failover, the decision layer of the whole pattern. Route 53
# probes the primary ALB from multiple locations; while the check
# passes, the failover record pair resolves to the primary. When it
# fails, resolution flips to the secondary ALB without any human or
# script in the loop. Recovering the data and compute layers behind
# that flip is the runbook's job.

# The check targets the primary ALB hostname directly, not the public
# domain name. Probing the domain would go through the very record this
# check controls and make the signal circular.
resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_alb_dns_name
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  enable_sni        = true
  request_interval  = 10
  failure_threshold = 2

  tags = { Name = "${var.name}-primary" }
}

resource "aws_route53_record" "primary" {
  zone_id        = var.hosted_zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary.id

  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

# evaluate_target_health stays false on purpose: at the moment of a
# failover the secondary has zero healthy targets because the pilot
# light is still scaling up. Evaluating its health would leave Route 53
# with no healthy answer at all; answering with the warming secondary
# is the better failure mode.
resource "aws_route53_record" "secondary" {
  zone_id        = var.hosted_zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  alias {
    name                   = var.secondary_alb_dns_name
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = false
  }
}

resource "aws_sns_topic" "failover" {
  provider = aws.us_east_1

  name = "${var.name}-failover"
}

resource "aws_sns_topic_subscription" "email" {
  count    = var.alarm_email == "" ? 0 : 1
  provider = aws.us_east_1

  topic_arn = aws_sns_topic.failover.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# This alarm is the pager. DNS failover happens on its own, but a human
# still has to promote the replica and scale the secondary ASG, so the
# time between this notification and someone running the runbook is
# pure RTO.
resource "aws_cloudwatch_metric_alarm" "primary_unhealthy" {
  provider = aws.us_east_1

  alarm_name          = "${var.name}-primary-region-unhealthy"
  alarm_description   = "Primary region failed its Route 53 health check. DNS has failed over; run the failover runbook now."
  namespace           = "AWS/Route53"
  metric_name         = "HealthCheckStatus"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    HealthCheckId = aws_route53_health_check.primary.id
  }

  alarm_actions = [aws_sns_topic.failover.arn]
  ok_actions    = [aws_sns_topic.failover.arn]
}
