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

locals {
  common_tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
    DrPattern = "pilot-light"
  }
}
