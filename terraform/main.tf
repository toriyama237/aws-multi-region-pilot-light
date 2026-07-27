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
