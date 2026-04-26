# modules/aws/networking/variables.tf

variable "environment" {
  description = "Environment name (prod, staging, dev). Used in resource naming."
  type        = string
  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "Environment must be one of: prod, staging, dev."
  }
}

variable "tgw_asn" {
  description = "BGP ASN for the Transit Gateway. Must not conflict with on-premises or Azure ASNs."
  type        = number
  default     = 64512
}

variable "organization_arn" {
  description = "ARN of the AWS Organization. Used to share TGW via RAM."
  type        = string
}

variable "egress_vpc_cidr" {
  description = "CIDR block for the centralised egress VPC."
  type        = string
  default     = "10.48.0.0/20"

  validation {
    condition     = can(cidrhost(var.egress_vpc_cidr, 0))
    error_message = "egress_vpc_cidr must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "List of AZs to deploy egress subnets into. Minimum 2 for HA."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones required for HA."
  }
}

variable "common_tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    ManagedBy  = "terraform"
    Repository = "multi-cloud-landing-zone"
    Module     = "aws/networking"
  }
}
