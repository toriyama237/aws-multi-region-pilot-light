output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_zone_id" {
  value = aws_lb.this.zone_id
}

output "asg_name" {
  value = aws_autoscaling_group.api.name
}

output "target_group_arn" {
  value = aws_lb_target_group.api.arn
}
