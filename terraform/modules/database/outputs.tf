output "primary_endpoint" {
  value = aws_db_instance.primary.address
}

output "primary_arn" {
  value = aws_db_instance.primary.arn
}

output "replica_endpoint" {
  value = aws_db_instance.replica.address
}

output "replica_identifier" {
  value = aws_db_instance.replica.identifier
}

output "secret_arn" {
  value = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  value = aws_secretsmanager_secret.db.name
}

output "db_name" {
  value = var.db_name
}

output "username" {
  value = var.username
}
