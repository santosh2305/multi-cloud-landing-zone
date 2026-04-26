# modules/aws/security/main.tf
#
# Deploys org-wide security controls:
#   - GuardDuty (delegated admin to Security account)
#   - AWS Config (org-wide rules, findings to Log Archive)
#   - Security Hub (aggregates findings from all accounts)
#   - IAM password policy
#
# Applied from the management account, delegates admin to security account.

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
# GuardDuty — Org-wide
# ---------------------------------------------------------------------------

resource "aws_guardduty_organization_admin_account" "security" {
  admin_account_id = var.security_account_id
}

resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      auto_enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          auto_enable = true
        }
      }
    }
  }

  tags = merge(var.common_tags, {
    Name = "guardduty-management-account"
  })
}

resource "aws_guardduty_organization_configuration" "main" {
  auto_enable_organization_members = "ALL"
  detector_id                      = aws_guardduty_detector.main.id

  datasources {
    s3_logs {
      auto_enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          auto_enable = true
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Security Hub — Org-wide
# ---------------------------------------------------------------------------

resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_organization_admin_account" "security" {
  admin_account_id = var.security_account_id
  depends_on       = [aws_securityhub_account.main]
}

# Enable CIS AWS Foundations Benchmark
resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.main]
}

# Enable AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.main]
}

# ---------------------------------------------------------------------------
# AWS Config — Org-wide rules
# ---------------------------------------------------------------------------

resource "aws_config_configuration_recorder" "main" {
  name     = "org-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  name           = "org-config-delivery"
  s3_bucket_name = var.log_archive_bucket_name
  s3_key_prefix  = "aws-config"

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  name       = aws_config_configuration_recorder.main.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}

# Key Config rules for energy sector compliance

resource "aws_config_config_rule" "s3_bucket_public_access_prohibited" {
  name        = "s3-bucket-public-access-prohibited"
  description = "Checks S3 buckets have public access block enabled."

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "encrypted_volumes" {
  name        = "encrypted-volumes"
  description = "Checks EBS volumes attached to EC2 instances are encrypted."

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "iam_password_policy" {
  name        = "iam-password-policy"
  description = "Checks IAM password policy meets minimum requirements."

  source {
    owner             = "AWS"
    source_identifier = "IAM_PASSWORD_POLICY"
  }

  input_parameters = jsonencode({
    RequireUppercaseCharacters = "true"
    RequireLowercaseCharacters = "true"
    RequireSymbols             = "true"
    RequireNumbers             = "true"
    MinimumPasswordLength      = "14"
    PasswordReusePrevention    = "24"
    MaxPasswordAge             = "90"
  })

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "mfa_enabled_for_iam_console_access" {
  name        = "mfa-enabled-for-iam-console-access"
  description = "Checks MFA is enabled for all IAM users with console access."

  source {
    owner             = "AWS"
    source_identifier = "MFA_ENABLED_FOR_IAM_CONSOLE_ACCESS"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "restricted_ssh" {
  name        = "restricted-ssh"
  description = "Checks security groups do not permit unrestricted SSH access."

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# ---------------------------------------------------------------------------
# IAM Role for Config
# ---------------------------------------------------------------------------

data "aws_region" "current" {}

resource "aws_iam_role" "config" {
  name = "aws-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_s3" {
  name = "config-s3-delivery"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "arn:aws:s3:::${var.log_archive_bucket_name}/aws-config/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::${var.log_archive_bucket_name}"
      }
    ]
  })
}
