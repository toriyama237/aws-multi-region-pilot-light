# Root composition. Each module is instantiated once per region with an
# explicit provider, so the file reads as a map of what exists where.
# The asymmetry between the two regions is the pilot light pattern
# itself: same network shape everywhere, full compute only in the
# primary, data replication towards the secondary.

module "network_primary" {
  source = "./modules/network"

  name       = "${var.project_name}-primary"
  cidr_block = var.primary_vpc_cidr
}

module "network_secondary" {
  source = "./modules/network"
  providers = {
    aws = aws.secondary
  }

  name       = "${var.project_name}-secondary"
  cidr_block = var.secondary_vpc_cidr
}

module "database" {
  source = "./modules/database"
  providers = {
    aws.primary   = aws
    aws.secondary = aws.secondary
  }

  name             = var.project_name
  db_name          = var.db_name
  username         = var.db_username
  instance_class   = var.db_instance_class
  secondary_region = var.secondary_region

  primary_vpc_id       = module.network_primary.vpc_id
  primary_subnet_ids   = module.network_primary.private_subnet_ids
  secondary_vpc_id     = module.network_secondary.vpc_id
  secondary_subnet_ids = module.network_secondary.private_subnet_ids

  primary_app_security_group_id   = aws_security_group.app_primary.id
  secondary_app_security_group_id = aws_security_group.app_secondary.id
}

module "storage" {
  source = "./modules/storage"
  providers = {
    aws.primary   = aws
    aws.secondary = aws.secondary
  }

  name = var.project_name
}

module "compute_primary" {
  source = "./modules/compute"

  name                  = "${var.project_name}-primary"
  vpc_id                = module.network_primary.vpc_id
  public_subnet_ids     = module.network_primary.public_subnet_ids
  private_subnet_ids    = module.network_primary.private_subnet_ids
  app_security_group_id = aws_security_group.app_primary.id

  instance_type    = var.app_instance_type
  desired_capacity = var.primary_desired_capacity

  domain_name    = var.domain_name
  hosted_zone_id = var.hosted_zone_id

  db_host        = module.database.primary_endpoint
  db_secret_name = module.database.secret_name
}

# The pilot light itself: same shape as the primary, zero instances.
# The ASG, launch template, ALB and certificate all exist and are
# tested, so a failover is a scale-up plus a database promotion, not a
# deployment.
module "compute_secondary" {
  source = "./modules/compute"
  providers = {
    aws = aws.secondary
  }

  name                  = "${var.project_name}-secondary"
  vpc_id                = module.network_secondary.vpc_id
  public_subnet_ids     = module.network_secondary.public_subnet_ids
  private_subnet_ids    = module.network_secondary.private_subnet_ids
  app_security_group_id = aws_security_group.app_secondary.id

  instance_type    = var.app_instance_type
  desired_capacity = 0

  domain_name    = var.domain_name
  hosted_zone_id = var.hosted_zone_id

  # Points at the replica. The endpoint survives promotion, so the
  # secondary stack needs no reconfiguration when the replica becomes
  # the new primary.
  db_host        = module.database.replica_endpoint
  db_secret_name = module.database.secret_name
}
