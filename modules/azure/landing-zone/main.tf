# modules/azure/landing-zone/main.tf
#
# Deploys the Azure Management Group hierarchy, Policy Initiatives,
# and subscription governance baseline.
#
# See ADR-001 (account strategy) and ADR-005 (data residency).
#
# Prerequisites:
#   - Azure CLI logged in with Owner on root Management Group
#   - Azure AD tenant already exists
#   - Terraform azurerm provider configured with service principal

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.47"
    }
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {}

# ---------------------------------------------------------------------------
# Management Group Hierarchy
# Mirrors the AWS OU structure for operational consistency (ADR-001)
# ---------------------------------------------------------------------------

resource "azurerm_management_group" "root" {
  display_name = var.root_management_group_name
}

resource "azurerm_management_group" "platform" {
  display_name               = "Platform"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "connectivity" {
  display_name               = "Connectivity"
  parent_management_group_id = azurerm_management_group.platform.id
}

resource "azurerm_management_group" "management" {
  display_name               = "Management"
  parent_management_group_id = azurerm_management_group.platform.id
}

resource "azurerm_management_group" "identity" {
  display_name               = "Identity"
  parent_management_group_id = azurerm_management_group.platform.id
}

resource "azurerm_management_group" "landing_zones" {
  display_name               = "LandingZones"
  parent_management_group_id = azurerm_management_group.root.id
}

resource "azurerm_management_group" "production" {
  display_name               = "Production"
  parent_management_group_id = azurerm_management_group.landing_zones.id
}

resource "azurerm_management_group" "non_production" {
  display_name               = "NonProduction"
  parent_management_group_id = azurerm_management_group.landing_zones.id
}

resource "azurerm_management_group" "decommissioned" {
  display_name               = "Decommissioned"
  parent_management_group_id = azurerm_management_group.root.id
}

# ---------------------------------------------------------------------------
# Policy: Data Residency — Deny non-approved regions (ADR-005)
# ---------------------------------------------------------------------------

resource "azurerm_policy_definition" "deny_non_approved_regions" {
  name         = "deny-non-approved-regions"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Deny resource creation outside approved regions"
  description  = "Enforces EU data residency. Denies creation of resources outside the approved region list. See ADR-005."

  metadata = jsonencode({
    version  = "1.0.0"
    category = "General"
  })

  policy_rule = jsonencode({
    if = {
      not = {
        field = "location"
        in    = var.approved_azure_regions
      }
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_management_group_policy_assignment" "deny_regions_root" {
  name                 = "deny-non-approved-regions"
  display_name         = "Deny resources outside approved EU regions"
  policy_definition_id = azurerm_policy_definition.deny_non_approved_regions.id
  management_group_id  = azurerm_management_group.root.id
  description          = "Enforces EU data residency at root MG level. Cannot be overridden by child MGs. See ADR-005."
}

# ---------------------------------------------------------------------------
# Policy: Require resource tagging
# ---------------------------------------------------------------------------

resource "azurerm_policy_definition" "require_tags" {
  name         = "require-mandatory-tags"
  policy_type  = "Custom"
  mode         = "Indexed"
  display_name = "Require mandatory resource tags"
  description  = "Denies resource creation without required tags: Environment, Owner, CostCentre, WorkloadDomain."

  metadata = jsonencode({
    version  = "1.0.0"
    category = "Tags"
  })

  policy_rule = jsonencode({
    if = {
      anyOf = [
        { field = "tags['Environment']", exists = "false" },
        { field = "tags['Owner']", exists = "false" },
        { field = "tags['CostCentre']", exists = "false" },
        { field = "tags['WorkloadDomain']", exists = "false" }
      ]
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_management_group_policy_assignment" "require_tags_landing_zones" {
  name                 = "require-mandatory-tags"
  display_name         = "Require mandatory tags on all resources"
  policy_definition_id = azurerm_policy_definition.require_tags.id
  management_group_id  = azurerm_management_group.landing_zones.id
}

# ---------------------------------------------------------------------------
# Policy: Defender for Cloud — auto-provision agents
# ---------------------------------------------------------------------------

resource "azurerm_policy_definition" "enable_defender" {
  name         = "enable-defender-for-cloud"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Enable Microsoft Defender for Cloud on all subscriptions"
  description  = "Deploys Defender for Cloud standard tier on new subscriptions automatically."

  metadata = jsonencode({
    version  = "1.0.0"
    category = "Security Center"
  })

  policy_rule = jsonencode({
    if = {
      field  = "type"
      equals = "Microsoft.Resources/subscriptions"
    }
    then = {
      effect = "deployIfNotExists"
      details = {
        type = "Microsoft.Security/pricings"
        name = "VirtualMachines"
        roleDefinitionIds = [
          "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        ]
        existenceCondition = {
          field  = "Microsoft.Security/pricings/pricingTier"
          equals = "Standard"
        }
        deployment = {
          properties = {
            mode     = "incremental"
            template = {}
          }
        }
      }
    }
  })
}

# ---------------------------------------------------------------------------
# Policy: Deny public IP on VMs
# ---------------------------------------------------------------------------

resource "azurerm_policy_definition" "deny_public_ip_on_vm" {
  name         = "deny-public-ip-on-vm"
  policy_type  = "Custom"
  mode         = "All"
  display_name = "Deny public IP addresses on virtual machines"
  description  = "VMs must not have public IPs. Internet access must route via Azure Firewall in the vWAN hub."

  metadata = jsonencode({
    version  = "1.0.0"
    category = "Network"
  })

  policy_rule = jsonencode({
    if = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Network/networkInterfaces"
        },
        {
          not = {
            field  = "Microsoft.Network/networkInterfaces/ipconfigurations[*].publicIpAddress.id"
            exists = "false"
          }
        }
      ]
    }
    then = {
      effect = "deny"
    }
  })
}

resource "azurerm_management_group_policy_assignment" "deny_public_ip_landing_zones" {
  name                 = "deny-public-ip-on-vm"
  display_name         = "Deny public IP addresses on VMs"
  policy_definition_id = azurerm_policy_definition.deny_public_ip_on_vm.id
  management_group_id  = azurerm_management_group.landing_zones.id
}
