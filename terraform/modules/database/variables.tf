variable "name" {
  description = "Prefix for every resource in the data layer."
  type        = string
}

variable "db_name" {
  description = "Name of the application database."
  type        = string
}

variable "username" {
  description = "Master username."
  type        = string
}

variable "instance_class" {
  description = "Instance class applied to both the primary and the replica."
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.6"
}

variable "multi_az" {
  description = "Whether the primary instance is Multi-AZ. Off by default to keep the demo cheap; the trade-off is discussed in the Well-Architected review."
  type        = bool
  default     = false
}

variable "secondary_region" {
  description = "Region the credentials secret is replicated to."
  type        = string
}

variable "primary_subnet_ids" {
  description = "Private subnets of the primary VPC."
  type        = list(string)
}

variable "secondary_subnet_ids" {
  description = "Private subnets of the secondary VPC."
  type        = list(string)
}

variable "primary_vpc_id" {
  type = string
}

variable "secondary_vpc_id" {
  type = string
}

variable "primary_app_security_group_id" {
  description = "Security group of the API instances in the primary region, the only ingress allowed on 5432."
  type        = string
}

variable "secondary_app_security_group_id" {
  description = "Security group of the API instances in the secondary region."
  type        = string
}
