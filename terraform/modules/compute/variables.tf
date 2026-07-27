variable "name" {
  description = "Prefix for every resource in this tier."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Subnets hosting the ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Subnets hosting the API instances."
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security group attached to the API instances, shared with the database module."
  type        = string
}

variable "instance_type" {
  type = string
}

variable "desired_capacity" {
  description = "Number of API instances. Zero in the pilot light region."
  type        = number
}

variable "max_size" {
  description = "Upper bound for the ASG, high enough to absorb full production traffic after a failover."
  type        = number
  default     = 4
}

variable "domain_name" {
  description = "Public FQDN of the API, used for the regional ACM certificate."
  type        = string
}

variable "hosted_zone_id" {
  description = "Route 53 zone used for ACM DNS validation."
  type        = string
}

variable "db_host" {
  description = "PostgreSQL endpoint local to this region."
  type        = string
}

variable "db_secret_name" {
  description = "Secrets Manager secret holding the database credentials. The name is identical in both regions thanks to secret replication."
  type        = string
}

variable "repo_url" {
  description = "Public repository the instances clone at boot to fetch the application."
  type        = string
  default     = "https://github.com/toriyama237/aws-multi-region-pilot-light.git"
}
