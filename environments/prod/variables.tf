# environments/prod/variables.tf

variable "cost_centre" {
  description = "Cost centre code for billing attribution."
  type        = string
}

variable "aws_organization_arn" {
  description = "ARN of the AWS Organization."
  type        = string
}

variable "security_account_id" {
  description = "AWS account ID of the Security/Audit account."
  type        = string
}

variable "log_archive_bucket_name" {
  description = "Name of the centralised log archive S3 bucket."
  type        = string
}

variable "connectivity_subscription_id" {
  description = "Azure subscription ID for Connectivity subscription."
  type        = string
  sensitive   = true
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace resource ID."
  type        = string
}

variable "aws_tgw_vpn_ip_1" {
  description = "AWS TGW VPN public IP (tunnel 1)."
  type        = string
}

variable "aws_tgw_vpn_ip_2" {
  description = "AWS TGW VPN public IP (tunnel 2)."
  type        = string
}

variable "aws_tgw_bgp_ip_1" {
  description = "AWS TGW BGP inside tunnel IP (tunnel 1)."
  type        = string
}

variable "aws_tgw_bgp_ip_2" {
  description = "AWS TGW BGP inside tunnel IP (tunnel 2)."
  type        = string
}

variable "vpn_shared_key" {
  description = "Pre-shared key for cross-cloud VPN. Read from Key Vault in CI/CD."
  type        = string
  sensitive   = true
}
