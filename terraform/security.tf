# The API instance security groups live at the root because two modules
# need them: the compute module attaches them to instances and adds the
# ALB ingress rule, the database module references them as the only
# source allowed on 5432. Declaring them here avoids a dependency cycle
# between the two modules.

resource "aws_security_group" "app_primary" {
  name        = "${var.project_name}-app-primary"
  description = "API instances, primary region"
  vpc_id      = module.network_primary.vpc_id

  egress {
    description = "Outbound to RDS, Secrets Manager and package mirrors"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app_secondary" {
  provider = aws.secondary

  name        = "${var.project_name}-app-secondary"
  description = "API instances, secondary region"
  vpc_id      = module.network_secondary.vpc_id

  egress {
    description = "Outbound to RDS, Secrets Manager and package mirrors"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
