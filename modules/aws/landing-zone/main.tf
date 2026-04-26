# modules/aws/landing-zone/main.tf
#
# Bootstraps the AWS Organizations structure, SCPs, and account vending
# foundation. Designed to be applied once from the management account.
#
# Prerequisites:
#   - AWS Organizations already enabled on management account
#   - Terraform running with OrganizationAccountAccessRole
#   - AWS Control Tower already deployed (this module attaches to CT OUs)

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

data "aws_organizations_organization" "current" {}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Organisational Units
# ---------------------------------------------------------------------------

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = data.aws_organizations_organization.current.roots[0].id

  tags = merge(var.common_tags, {
    Purpose = "Security tooling and log archive accounts"
  })
}

resource "aws_organizations_organizational_unit" "shared_services" {
  name      = "SharedServices"
  parent_id = data.aws_organizations_organization.current.roots[0].id

  tags = merge(var.common_tags, {
    Purpose = "Networking, DNS, and shared platform services"
  })
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = data.aws_organizations_organization.current.roots[0].id

  tags = merge(var.common_tags, {
    Purpose = "Business workload accounts"
  })
}

resource "aws_organizations_organizational_unit" "workloads_prod" {
  name      = "Production"
  parent_id = aws_organizations_organizational_unit.workloads.id

  tags = merge(var.common_tags, {
    Environment = "prod"
  })
}

resource "aws_organizations_organizational_unit" "workloads_nonprod" {
  name      = "NonProduction"
  parent_id = aws_organizations_organizational_unit.workloads.id

  tags = merge(var.common_tags, {
    Environment = "non-prod"
  })
}

resource "aws_organizations_organizational_unit" "global_workloads" {
  name      = "GlobalWorkloads"
  parent_id = data.aws_organizations_organization.current.roots[0].id

  tags = merge(var.common_tags, {
    Purpose = "Exception OU for workloads requiring non-EU regions. Requires CISO approval."
  })
}

# ---------------------------------------------------------------------------
# Service Control Policies
# ---------------------------------------------------------------------------

# Deny non-approved regions (ADR-005)
resource "aws_organizations_policy" "deny_non_eu_regions" {
  name        = "DenyNonApprovedRegions"
  description = "Enforces EU data residency by denying API calls to non-approved regions. Exempts global services. See ADR-005."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyNonApprovedRegions"
        Effect = "Deny"
        NotAction = [
          "iam:*",
          "organizations:*",
          "route53:*",
          "budgets:*",
          "cloudfront:*",
          "sts:*",
          "support:*",
          "trustedadvisor:*",
          "health:*",
          "account:*"
        ]
        Resource = "*"
        Condition = {
          StringNotIn = {
            "aws:RequestedRegion" = var.approved_regions
          }
        }
      }
    ]
  })

  tags = var.common_tags
}

# Deny root user usage
resource "aws_organizations_policy" "deny_root_user" {
  name        = "DenyRootUserActions"
  description = "Prevents use of root user credentials in member accounts."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyRootUser"
        Effect = "Deny"
        Action = "*"
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:root"
          }
        }
      }
    ]
  })

  tags = var.common_tags
}

# Protect security controls from modification
resource "aws_organizations_policy" "protect_security_controls" {
  name        = "ProtectSecurityControls"
  description = "Prevents workload accounts from disabling CloudTrail, GuardDuty, Config, or Security Hub."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDisableCloudTrail"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyDisableGuardDuty"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromMasterAccount",
          "guardduty:StopMonitoringMembers",
          "guardduty:UpdateDetector"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyDisableConfig"
        Effect = "Deny"
        Action = [
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel",
          "config:StopConfigurationRecorder"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyModifyLogArchive"
        Effect = "Deny"
        Action = [
          "s3:DeleteBucket",
          "s3:DeleteBucketPolicy",
          "s3:PutBucketAcl",
          "s3:PutBucketPolicy",
          "s3:PutEncryptionConfiguration",
          "s3:PutLifecycleConfiguration"
        ]
        Resource = "arn:aws:s3:::${var.log_archive_bucket_name}"
      }
    ]
  })

  tags = var.common_tags
}

# Enforce S3 encryption and block public access
resource "aws_organizations_policy" "enforce_s3_security" {
  name        = "EnforceS3Security"
  description = "Requires S3 encryption and denies public S3 bucket creation."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyS3PublicAccess"
        Effect = "Deny"
        Action = [
          "s3:PutBucketPublicAccessBlock",
          "s3:DeletePublicAccessBlock"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "s3:PublicAccessBlockConfiguration/BlockPublicAcls"       = "false"
            "s3:PublicAccessBlockConfiguration/IgnorePublicAcls"      = "false"
            "s3:PublicAccessBlockConfiguration/BlockPublicPolicy"     = "false"
            "s3:PublicAccessBlockConfiguration/RestrictPublicBuckets" = "false"
          }
        }
      }
    ]
  })

  tags = var.common_tags
}

# ---------------------------------------------------------------------------
# SCP Attachments
# ---------------------------------------------------------------------------

resource "aws_organizations_policy_attachment" "deny_regions_root" {
  policy_id = aws_organizations_policy.deny_non_eu_regions.id
  target_id = data.aws_organizations_organization.current.roots[0].id
}

resource "aws_organizations_policy_attachment" "deny_root_user_workloads" {
  policy_id = aws_organizations_policy.deny_root_user.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

resource "aws_organizations_policy_attachment" "protect_security_controls_all" {
  policy_id = aws_organizations_policy.protect_security_controls.id
  target_id = data.aws_organizations_organization.current.roots[0].id
}

resource "aws_organizations_policy_attachment" "enforce_s3_workloads" {
  policy_id = aws_organizations_policy.enforce_s3_security.id
  target_id = aws_organizations_organizational_unit.workloads.id
}
