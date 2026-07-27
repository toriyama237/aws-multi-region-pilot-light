variable "name" {
  type = string
}

variable "domain_name" {
  description = "Public FQDN served by the failover record pair."
  type        = string
}

variable "hosted_zone_id" {
  type = string
}

variable "primary_alb_dns_name" {
  type = string
}

variable "primary_alb_zone_id" {
  type = string
}

variable "secondary_alb_dns_name" {
  type = string
}

variable "secondary_alb_zone_id" {
  type = string
}

variable "alarm_email" {
  description = "Email notified when the primary health check fails. Empty disables the subscription."
  type        = string
  default     = ""
}
