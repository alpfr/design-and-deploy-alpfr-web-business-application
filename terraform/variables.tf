variable "domain_name" {
  description = "Apex domain for the site. www.<domain_name> is added automatically."
  type        = string
  default     = "alpfr.com"
}

variable "enable_custom_domain" {
  description = "false = preview on the cloudfront.net URL only. true = request a certificate and attach alpfr.com and www.alpfr.com to the distribution."
  type        = bool
  default     = false
}

variable "route53_zone_id" {
  description = "Route 53 hosted zone ID for the domain. If set, certificate validation and the DNS records for the site are created automatically. Leave empty if DNS is hosted elsewhere."
  type        = string
  default     = ""
}
