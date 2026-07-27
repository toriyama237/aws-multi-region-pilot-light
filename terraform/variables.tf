variable "project_name" {
  description = "Short name used as a prefix for every resource."
  type        = string
  default     = "notes"
}

variable "primary_region" {
  description = "Region serving all traffic in nominal conditions."
  type        = string
  default     = "eu-west-1"
}

variable "secondary_region" {
  description = "Pilot light region. Data replicates here continuously, compute stays at zero."
  type        = string
  default     = "eu-west-3"
}

# The two VPCs use disjoint CIDR blocks on purpose. Nothing requires it
# today, but it keeps VPC peering or Transit Gateway on the table without
# a renumbering project later.
variable "primary_vpc_cidr" {
  description = "CIDR block of the primary VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "secondary_vpc_cidr" {
  description = "CIDR block of the secondary VPC."
  type        = string
  default     = "10.1.0.0/16"
}

variable "domain_name" {
  description = "Public FQDN of the API, for example api.example.com."
  type        = string
}

variable "hosted_zone_id" {
  description = "ID of the existing Route 53 public hosted zone that owns domain_name."
  type        = string
}

variable "app_instance_type" {
  description = "Instance type for the API tier."
  type        = string
  default     = "t3.micro"
}

variable "primary_desired_capacity" {
  description = "Number of API instances in the primary region."
  type        = number
  default     = 2
}

variable "db_instance_class" {
  description = "RDS instance class, applied to the primary and the replica."
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Name of the application database."
  type        = string
  default     = "notes"
}

variable "db_username" {
  description = "Master username of the RDS instance."
  type        = string
  default     = "notes_admin"
}

variable "alarm_email" {
  description = "Email address subscribed to failover and replication lag alarms."
  type        = string
  default     = ""
}
