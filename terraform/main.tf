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
