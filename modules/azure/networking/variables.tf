# modules/azure/networking/variables.tf

variable "environment" {
  description = "Environment name."
  type        = string
  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "Environment must be one of: prod, staging, dev."
  }
}

variable "connectivity_subscription_id" {
  description = "Azure subscription ID for the Connectivity subscription."
  type        = string
  sensitive   = true
}

variable "primary_location" {
  description = "Primary Azure region."
  type        = string
  default     = "westeurope"
}

variable "primary_location_short" {
  description = "Short name for primary region used in resource naming."
  type        = string
  default     = "weu"
}

variable "dr_location" {
  description = "DR Azure region."
  type        = string
  default     = "northeurope"
}

variable "dr_location_short" {
  description = "Short name for DR region."
  type        = string
  default     = "neu"
}

variable "primary_hub_cidr" {
  description = "CIDR block for the primary vWAN hub. Must not overlap with any VNets or on-premises."
  type        = string
  default     = "10.16.0.0/23"
}

variable "dr_hub_cidr" {
  description = "CIDR block for the DR vWAN hub."
  type        = string
  default     = "10.16.2.0/23"
}

variable "deploy_dr_hub" {
  description = "Whether to deploy the DR hub. Set false for dev/staging to reduce cost."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace resource ID for Firewall diagnostics."
  type        = string
}

variable "vpn_scale_unit" {
  description = "Scale unit for VPN gateway. 1 = 500Mbps aggregate."
  type        = number
  default     = 1
}

variable "azure_bgp_asn" {
  description = "BGP ASN for Azure VPN gateway. Must not conflict with AWS TGW or on-premises ASNs."
  type        = number
  default     = 65515
}

variable "aws_address_space" {
  description = "AWS VPC CIDR blocks to advertise via BGP."
  type        = list(string)
  default     = ["10.0.0.0/12"]
}

variable "aws_tgw_vpn_ip_1" {
  description = "Public IP of AWS Transit Gateway VPN attachment (tunnel 1)."
  type        = string
}

variable "aws_tgw_vpn_ip_2" {
  description = "Public IP of AWS Transit Gateway VPN attachment (tunnel 2)."
  type        = string
}

variable "aws_tgw_bgp_asn" {
  description = "BGP ASN configured on the AWS Transit Gateway."
  type        = number
  default     = 64512
}

variable "aws_tgw_bgp_ip_1" {
  description = "BGP peering IP on the AWS TGW (tunnel 1)."
  type        = string
}

variable "aws_tgw_bgp_ip_2" {
  description = "BGP peering IP on the AWS TGW (tunnel 2)."
  type        = string
}

variable "vpn_shared_key" {
  description = "Pre-shared key for IPsec VPN tunnels. Must match AWS TGW VPN configuration. Store in Key Vault."
  type        = string
  sensitive   = true
}

variable "common_tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    ManagedBy  = "terraform"
    Repository = "multi-cloud-landing-zone"
    Module     = "azure/networking"
  }
}
