# environments/prod/main.tf
#
# Production environment root module.
# Orchestrates all landing zone modules for the production environment.

terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    # Configure via -backend-config flags or backend.hcl (not checked in)
    # bucket         = "your-tfstate-bucket"
    # key            = "landing-zone/prod/terraform.tfstate"
    # region         = "eu-west-1"
    # dynamodb_table = "terraform-locks"
    # encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
}

provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      Environment    = "prod"
      ManagedBy      = "terraform"
      Repository     = "multi-cloud-landing-zone"
      CostCentre     = var.cost_centre
      WorkloadDomain = "platform"
    }
  }
}

provider "azurerm" {
  features {}
}

# ---------------------------------------------------------------------------
# AWS Landing Zone
# ---------------------------------------------------------------------------

module "aws_landing_zone" {
  source = "../../modules/aws/landing-zone"

  approved_regions        = ["eu-west-1", "eu-central-1", "eu-west-2"]
  log_archive_bucket_name = var.log_archive_bucket_name

  common_tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
    Repository  = "multi-cloud-landing-zone"
  }
}

# ---------------------------------------------------------------------------
# AWS Networking
# ---------------------------------------------------------------------------

module "aws_networking" {
  source = "../../modules/aws/networking"

  environment        = "prod"
  tgw_asn            = 64512
  organization_arn   = var.aws_organization_arn
  egress_vpc_cidr    = "10.48.0.0/20"
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  common_tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# AWS Security
# ---------------------------------------------------------------------------

module "aws_security" {
  source = "../../modules/aws/security"

  security_account_id     = var.security_account_id
  log_archive_bucket_name = var.log_archive_bucket_name

  common_tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Azure Landing Zone
# ---------------------------------------------------------------------------

module "azure_landing_zone" {
  source = "../../modules/azure/landing-zone"

  root_management_group_name = "ContsoEnergy"
  approved_azure_regions     = ["westeurope", "northeurope", "uksouth", "global"]

  common_tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}

# ---------------------------------------------------------------------------
# Azure Networking
# ---------------------------------------------------------------------------

module "azure_networking" {
  source = "../../modules/azure/networking"

  environment                  = "prod"
  connectivity_subscription_id = var.connectivity_subscription_id
  primary_location             = "westeurope"
  primary_location_short       = "weu"
  dr_location                  = "northeurope"
  dr_location_short            = "neu"
  primary_hub_cidr             = "10.16.0.0/23"
  dr_hub_cidr                  = "10.16.2.0/23"
  deploy_dr_hub                = true
  log_analytics_workspace_id   = var.log_analytics_workspace_id
  vpn_scale_unit               = 2 # 2 = 1Gbps aggregate for prod

  # AWS TGW cross-cloud VPN (outputs from aws_networking module)
  aws_tgw_vpn_ip_1 = var.aws_tgw_vpn_ip_1
  aws_tgw_vpn_ip_2 = var.aws_tgw_vpn_ip_2
  aws_tgw_bgp_asn  = 64512
  aws_tgw_bgp_ip_1 = var.aws_tgw_bgp_ip_1
  aws_tgw_bgp_ip_2 = var.aws_tgw_bgp_ip_2
  vpn_shared_key   = var.vpn_shared_key

  common_tags = {
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
