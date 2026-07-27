variable "name" {
  description = "Prefix for every resource in this VPC."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block of the VPC. Public and private subnets are carved out of it."
  type        = string
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across."
  type        = number
  default     = 2
}
