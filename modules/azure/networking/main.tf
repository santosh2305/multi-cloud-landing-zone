# modules/azure/networking/main.tf
#
# Deploys the Azure Virtual WAN hub-and-spoke topology.
# See ADR-003 for topology decision rationale.
#
# This module deploys into the dedicated Connectivity subscription.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.connectivity_subscription_id
}

# ---------------------------------------------------------------------------
# Resource Group
# ---------------------------------------------------------------------------

resource "azurerm_resource_group" "connectivity" {
  name     = "rg-connectivity-${var.environment}"
  location = var.primary_location

  tags = merge(var.common_tags, {
    Environment = var.environment
    Purpose     = "Connectivity - vWAN, hubs, and VPN gateways"
  })
}

# ---------------------------------------------------------------------------
# Virtual WAN
# ---------------------------------------------------------------------------

resource "azurerm_virtual_wan" "main" {
  name                = "vwan-${var.environment}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = var.primary_location

  allow_branch_to_branch_traffic = true
  type                           = "Standard" # Standard required for Azure Firewall integration

  tags = merge(var.common_tags, {
    Name = "vwan-${var.environment}"
  })
}

# ---------------------------------------------------------------------------
# Virtual Hub — Primary Region
# ---------------------------------------------------------------------------

resource "azurerm_virtual_hub" "primary" {
  name                = "vhub-${var.environment}-${var.primary_location_short}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = var.primary_location
  virtual_wan_id      = azurerm_virtual_wan.main.id
  address_prefix      = var.primary_hub_cidr

  tags = merge(var.common_tags, {
    Region = var.primary_location
    Role   = "primary-hub"
  })
}

# Virtual Hub — DR Region
resource "azurerm_virtual_hub" "dr" {
  count = var.deploy_dr_hub ? 1 : 0

  name                = "vhub-${var.environment}-${var.dr_location_short}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = var.dr_location
  virtual_wan_id      = azurerm_virtual_wan.main.id
  address_prefix      = var.dr_hub_cidr

  tags = merge(var.common_tags, {
    Region = var.dr_location
    Role   = "dr-hub"
  })
}

# ---------------------------------------------------------------------------
# Azure Firewall in primary hub
# ---------------------------------------------------------------------------

resource "azurerm_firewall_policy" "main" {
  name                = "afwp-${var.environment}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = var.primary_location
  sku                 = "Premium" # Premium for IDPS and TLS inspection

  insights {
    enabled                            = true
    default_log_analytics_workspace_id = var.log_analytics_workspace_id
    retention_days                     = 30
  }

  intrusion_detection {
    mode = "Alert" # Change to "Deny" after tuning baseline
  }

  tags = var.common_tags
}

resource "azurerm_virtual_hub_ip" "firewall" {
  name                         = "afw-${var.environment}-${var.primary_location_short}"
  virtual_hub_id               = azurerm_virtual_hub.primary.id
  private_ip_allocation_method = "Dynamic"
  subnet_id                    = azurerm_subnet.firewall[0].id
  public_ip_address_id         = azurerm_public_ip.firewall.id
}

resource "azurerm_public_ip" "firewall" {
  name                = "pip-afw-${var.environment}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = var.primary_location
  allocation_method   = "Static"
  sku                 = "Standard"

  tags = var.common_tags
}

# Placeholder subnet reference — in vWAN the firewall is integrated into the hub
resource "azurerm_subnet" "firewall" {
  count = 1

  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.connectivity.name
  virtual_network_name = azurerm_virtual_network.hub_vnet[0].name
  address_prefixes     = [cidrsubnet(var.primary_hub_cidr, 2, 0)]
}

resource "azurerm_virtual_network" "hub_vnet" {
  count = 1

  name                = "vnet-hub-${var.environment}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = var.primary_location
  address_space       = [var.primary_hub_cidr]

  tags = var.common_tags
}

# ---------------------------------------------------------------------------
# VPN Gateway in vWAN hub (for on-premises + AWS connectivity)
# ---------------------------------------------------------------------------

resource "azurerm_vpn_gateway" "primary" {
  name                = "vpng-${var.environment}-${var.primary_location_short}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = var.primary_location
  virtual_hub_id      = azurerm_virtual_hub.primary.id
  scale_unit          = var.vpn_scale_unit

  bgp_settings {
    asn         = var.azure_bgp_asn
    peer_weight = 0

    instance_0_bgp_peering_address {
      custom_ips = [cidrhost(var.primary_hub_cidr, 228)]
    }

    instance_1_bgp_peering_address {
      custom_ips = [cidrhost(var.primary_hub_cidr, 229)]
    }
  }

  tags = var.common_tags
}

# ---------------------------------------------------------------------------
# VPN Site — AWS Transit Gateway
# Establishes the cross-cloud IPsec tunnel (ADR-003)
# ---------------------------------------------------------------------------

resource "azurerm_vpn_site" "aws_tgw" {
  name                = "vpnsite-aws-tgw-${var.environment}"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = var.primary_location
  virtual_wan_id      = azurerm_virtual_wan.main.id

  address_cidrs = var.aws_address_space

  link {
    name       = "aws-tgw-link-1"
    ip_address = var.aws_tgw_vpn_ip_1
    speed_in_mbps = 500

    bgp {
      asn             = var.aws_tgw_bgp_asn
      peering_address = var.aws_tgw_bgp_ip_1
    }
  }

  link {
    name       = "aws-tgw-link-2"
    ip_address = var.aws_tgw_vpn_ip_2
    speed_in_mbps = 500

    bgp {
      asn             = var.aws_tgw_bgp_asn
      peering_address = var.aws_tgw_bgp_ip_2
    }
  }

  tags = merge(var.common_tags, {
    Purpose = "Cross-cloud VPN to AWS Transit Gateway"
  })
}

resource "azurerm_vpn_gateway_connection" "aws_tgw" {
  name               = "vpnconn-aws-tgw-${var.environment}"
  vpn_gateway_id     = azurerm_vpn_gateway.primary.id
  remote_vpn_site_id = azurerm_vpn_site.aws_tgw.id

  vpn_link {
    name             = "aws-tgw-link-1"
    vpn_site_link_id = azurerm_vpn_site.aws_tgw.link[0].id
    protocol         = "IKEv2"
    shared_key       = var.vpn_shared_key # Store in Azure Key Vault, pass as sensitive variable

    bgp_enabled = true

    ipsec_policy {
      dh_group                 = "DHGroup14"
      ike_encryption_algorithm = "AES256"
      ike_integrity_algorithm  = "SHA256"
      encryption_algorithm     = "AES256"
      integrity_algorithm      = "SHA256"
      pfs_group                = "PFS14"
      sa_lifetime_in_seconds   = 3600
    }
  }

  vpn_link {
    name             = "aws-tgw-link-2"
    vpn_site_link_id = azurerm_vpn_site.aws_tgw.link[1].id
    protocol         = "IKEv2"
    shared_key       = var.vpn_shared_key
    bgp_enabled      = true

    ipsec_policy {
      dh_group                 = "DHGroup14"
      ike_encryption_algorithm = "AES256"
      ike_integrity_algorithm  = "SHA256"
      encryption_algorithm     = "AES256"
      integrity_algorithm      = "SHA256"
      pfs_group                = "PFS14"
      sa_lifetime_in_seconds   = 3600
    }
  }
}
