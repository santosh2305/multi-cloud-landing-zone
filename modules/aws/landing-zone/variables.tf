# modules/aws/landing-zone/variables.tf

variable "approved_regions" {
  description = "List of AWS regions permitted under data residency policy (ADR-005). Defaults to EU regions."
  type        = list(string)
  default     = ["eu-west-1", "eu-central-1", "eu-west-2"]
}

variable "log_archive_bucket_name" {
  description = "Name of the centralised log archive S3 bucket in the Security account. Used in SCP to prevent modification."
  type        = string
}

variable "common_tags" {
  description = "Tags applied to all resources in this module."
  type        = map(string)
  default = {
    ManagedBy   = "terraform"
    Repository  = "multi-cloud-landing-zone"
    Module      = "aws/landing-zone"
  }
}
