# Data layer of the pilot light. The primary region runs a writable
# PostgreSQL instance, the secondary region runs a cross-region read
# replica that replicates asynchronously. Promotion of that replica is
# the data side of a failover and is handled by the runbook, not by
# Terraform, because it is a one-way operational decision.

# Credentials are generated once and stored in Secrets Manager with a
# native replica in the secondary region, so the promoted stack can read
# them even if the primary region is entirely unavailable.
resource "random_password" "master" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "db" {
  provider = aws.primary

  name        = "${var.name}/database"
  description = "Master credentials for the ${var.name} PostgreSQL instance."

  replica {
    region = var.secondary_region
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  provider = aws.primary

  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.username
    password = random_password.master.result
    dbname   = var.db_name
    port     = 5432
  })
}

# One customer managed KMS key per region. A cross-region replica cannot
# use the source key, KMS keys never leave their region, so the replica
# is re-encrypted with its own key at creation time.
resource "aws_kms_key" "primary" {
  provider = aws.primary

  description         = "${var.name} RDS encryption, primary region"
  enable_key_rotation = true
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description         = "${var.name} RDS encryption, secondary region"
  enable_key_rotation = true
}

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name       = "${var.name}-primary"
  subnet_ids = var.primary_subnet_ids
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name       = "${var.name}-secondary"
  subnet_ids = var.secondary_subnet_ids
}

resource "aws_security_group" "primary" {
  provider = aws.primary

  name        = "${var.name}-db-primary"
  description = "PostgreSQL ingress from the API tier only"
  vpc_id      = var.primary_vpc_id

  ingress {
    description     = "PostgreSQL from API instances"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.primary_app_security_group_id]
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${var.name}-db-secondary"
  description = "PostgreSQL ingress from the API tier only"
  vpc_id      = var.secondary_vpc_id

  ingress {
    description     = "PostgreSQL from API instances"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.secondary_app_security_group_id]
  }
}

resource "aws_db_instance" "primary" {
  provider = aws.primary

  identifier     = "${var.name}-primary"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.username
  password = random_password.master.result

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.primary.arn

  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.primary.id]
  multi_az               = var.multi_az
  publicly_accessible    = false

  # Automated backups are not optional here: a source instance must have
  # them enabled for a cross-region read replica to exist at all.
  backup_retention_period  = 7
  delete_automated_backups = true

  auto_minor_version_upgrade = true
  apply_immediately          = true

  # Demo setting. In production this would be true and paired with
  # deletion_protection, both discussed in the operational excellence
  # section of the review.
  skip_final_snapshot = true
}

resource "aws_db_instance" "replica" {
  provider = aws.secondary

  identifier          = "${var.name}-replica"
  replicate_source_db = aws_db_instance.primary.arn
  instance_class      = var.instance_class

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  db_subnet_group_name   = aws_db_subnet_group.secondary.name
  vpc_security_group_ids = [aws_security_group.secondary.id]
  publicly_accessible    = false

  # Retention above zero means the replica keeps taking backups, so the
  # instance is immediately restorable after a promotion instead of
  # starting its backup history from scratch mid-incident.
  backup_retention_period = 7

  auto_minor_version_upgrade = true
  skip_final_snapshot        = true
}
