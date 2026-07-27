# Everything the failover runbook and a demo walkthrough need, in one
# place. The script in scripts/failover.sh reads these outputs instead
# of hardcoding identifiers.

output "api_url" {
  description = "Public entry point, stable across failovers."
  value       = module.dns.api_url
}

output "primary_alb_dns_name" {
  value = module.compute_primary.alb_dns_name
}

output "secondary_alb_dns_name" {
  value = module.compute_secondary.alb_dns_name
}

output "primary_db_endpoint" {
  value = module.database.primary_endpoint
}

output "replica_db_endpoint" {
  value = module.database.replica_endpoint
}

output "replica_db_identifier" {
  description = "Identifier the runbook promotes during a failover."
  value       = module.database.replica_identifier
}

output "secondary_asg_name" {
  description = "Auto Scaling group the runbook scales up during a failover."
  value       = module.compute_secondary.asg_name
}

output "primary_asg_name" {
  value = module.compute_primary.asg_name
}

output "primary_bucket" {
  value = module.storage.primary_bucket
}

output "secondary_bucket" {
  value = module.storage.secondary_bucket
}

output "health_check_id" {
  value = module.dns.health_check_id
}
