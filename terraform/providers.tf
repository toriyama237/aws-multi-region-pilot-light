# Two providers, one per region. The default provider targets the primary
# region and the "secondary" alias targets the pilot light region. Every
# module call below picks one of the two explicitly, which keeps the
# regional split visible at a glance in main.tf.

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = local.common_tags
  }
}

# Route 53 is a global service but its health check metrics only exist
# in us-east-1, so the alarm watching the failover signal must live
# there regardless of the two workload regions.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
    DrPattern = "pilot-light"
  }
}
