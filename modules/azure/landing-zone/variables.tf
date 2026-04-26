# modules/azure/landing-zone/variables.tf

variable "root_management_group_name" {
  description = "Display name for the root management group."
  type        = string
  default     = "Contoso-Energy"
}

variable "approved_azure_regions" {
  description = "List of Azure regions permitted under data residency policy (ADR-005). Defaults to EU regions + 'global' for global services."
  type        = list(string)
  default     = ["westeurope", "northeurope", "uksouth", "global"]
}

variable "common_tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    ManagedBy  = "terraform"
    Repository = "multi-cloud-landing-zone"
    Module     = "azure/landing-zone"
  }
}
