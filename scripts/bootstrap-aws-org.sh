#!/usr/bin/env bash
# scripts/bootstrap-aws-org.sh
#
# Bootstraps the initial AWS Organizations setup before Terraform can manage it.
# Run this ONCE from the management account before running any Terraform.
#
# Prerequisites:
#   - AWS CLI configured with management account credentials
#   - OrganizationsFullAccess permissions
#
# Usage:
#   ./bootstrap-aws-org.sh --profile master-account [--region eu-west-1]

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

PROFILE=""
REGION="eu-west-1"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$PROFILE" ]]; then
  echo "Error: --profile is required"
  echo "Usage: $0 --profile <aws-profile> [--region <region>] [--dry-run]"
  exit 1
fi

AWS_CMD="aws --profile $PROFILE --region $REGION"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

check_prereqs() {
  log "Checking prerequisites..."

  if ! command -v aws &>/dev/null; then
    echo "Error: AWS CLI not found. Install from https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
    exit 1
  fi

  if ! command -v terraform &>/dev/null; then
    echo "Error: Terraform not found. Install from https://terraform.io/downloads"
    exit 1
  fi

  # Verify profile exists and credentials are valid
  if ! $AWS_CMD sts get-caller-identity &>/dev/null; then
    echo "Error: Cannot authenticate with profile '$PROFILE'. Check credentials."
    exit 1
  fi

  ACCOUNT_ID=$($AWS_CMD sts get-caller-identity --query Account --output text)
  log "Authenticated as account: $ACCOUNT_ID"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

check_prereqs

log "Starting AWS Organizations bootstrap..."
log "Profile: $PROFILE | Region: $REGION | Dry run: $DRY_RUN"

# Check if Organizations already exists
ORG_STATUS=$($AWS_CMD organizations describe-organization --query Organization.Id --output text 2>/dev/null || echo "NOT_EXISTS")

if [[ "$ORG_STATUS" == "NOT_EXISTS" ]]; then
  log "AWS Organizations not found. Creating..."
  if [[ "$DRY_RUN" == "false" ]]; then
    $AWS_CMD organizations create-organization --feature-set ALL
    log "AWS Organizations created."
  else
    log "[DRY RUN] Would create AWS Organizations"
  fi
else
  log "AWS Organizations already exists: $ORG_STATUS"
fi

# Enable trusted access for required services
TRUSTED_SERVICES=(
  "cloudtrail.amazonaws.com"
  "config.amazonaws.com"
  "guardduty.amazonaws.com"
  "securityhub.amazonaws.com"
  "ram.amazonaws.com"
  "sso.amazonaws.com"
  "ipam.amazonaws.com"
)

log "Enabling trusted access for AWS services..."
for service in "${TRUSTED_SERVICES[@]}"; do
  log "  Enabling: $service"
  if [[ "$DRY_RUN" == "false" ]]; then
    $AWS_CMD organizations enable-aws-service-access \
      --service-principal "$service" 2>/dev/null || true
  else
    log "  [DRY RUN] Would enable trusted access for $service"
  fi
done

# Create S3 state bucket if it doesn't exist
STATE_BUCKET="company-energy-tfstate-${ACCOUNT_ID}"
log "Checking Terraform state bucket: $STATE_BUCKET"

if ! $AWS_CMD s3 ls "s3://$STATE_BUCKET" &>/dev/null; then
  log "Creating Terraform state bucket..."
  if [[ "$DRY_RUN" == "false" ]]; then
    $AWS_CMD s3api create-bucket \
      --bucket "$STATE_BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"

    # Enable versioning
    $AWS_CMD s3api put-bucket-versioning \
      --bucket "$STATE_BUCKET" \
      --versioning-configuration Status=Enabled

    # Enable encryption
    $AWS_CMD s3api put-bucket-encryption \
      --bucket "$STATE_BUCKET" \
      --server-side-encryption-configuration '{
        "Rules": [{
          "ApplyServerSideEncryptionByDefault": {
            "SSEAlgorithm": "aws:kms"
          }
        }]
      }'

    # Block public access
    $AWS_CMD s3api put-public-access-block \
      --bucket "$STATE_BUCKET" \
      --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

    log "State bucket created: $STATE_BUCKET"
  else
    log "[DRY RUN] Would create state bucket: $STATE_BUCKET"
  fi
else
  log "State bucket already exists: $STATE_BUCKET"
fi

# Create DynamoDB lock table
LOCK_TABLE="terraform-locks"
log "Checking DynamoDB lock table: $LOCK_TABLE"

if ! $AWS_CMD dynamodb describe-table --table-name "$LOCK_TABLE" &>/dev/null; then
  log "Creating DynamoDB lock table..."
  if [[ "$DRY_RUN" == "false" ]]; then
    $AWS_CMD dynamodb create-table \
      --table-name "$LOCK_TABLE" \
      --attribute-definitions AttributeName=LockID,AttributeType=S \
      --key-schema AttributeName=LockID,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST \
      --tags Key=ManagedBy,Value=bootstrap Key=Repository,Value=multi-cloud-landing-zone

    log "DynamoDB lock table created."
  else
    log "[DRY RUN] Would create DynamoDB lock table: $LOCK_TABLE"
  fi
else
  log "DynamoDB lock table already exists: $LOCK_TABLE"
fi

# ---------------------------------------------------------------------------
# Output next steps
# ---------------------------------------------------------------------------

cat <<EOF

================================================================================
Bootstrap complete.

Next steps:
1. Update environments/prod/backend.hcl with:
   bucket         = "$STATE_BUCKET"
   dynamodb_table = "$LOCK_TABLE"
   region         = "$REGION"

2. Run Terraform:
   cd environments/prod
   terraform init -backend-config=backend.hcl
   terraform plan -var-file=prod.tfvars
   terraform apply -var-file=prod.tfvars

3. After landing zone is deployed, proceed with account vending:
   See docs/runbooks/new-account-onboarding.md
================================================================================
EOF
