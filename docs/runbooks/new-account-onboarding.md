# Runbook: Onboarding a New AWS Account / Azure Subscription

**Version:** 1.2  
**Last Updated:** 2024-05-10  
**Owner:** Platform Engineering  
**Review Cycle:** Quarterly  

---

## Overview

This runbook covers the end-to-end process for vending a new AWS account or Azure subscription into the landing zone. The process is mostly automated via Terraform, but requires manual steps for initial identity setup and verification.

**Estimated time:** 45–90 minutes (mostly waiting for propagation)

---

## Prerequisites

- [ ] Workload domain owner has submitted a request via the platform intake form
- [ ] Cost centre code confirmed with Finance
- [ ] Approved by Platform Architecture lead (for prod) or team lead (for non-prod)
- [ ] CIDR block reserved in the IPAM spreadsheet (pending automation)

---

## AWS Account Vending

### Step 1: Reserve CIDR Block

Log into the IPAM Google Sheet (link in internal wiki) and reserve a /20 CIDR from the appropriate range:

| Environment | Range | Allocation |
|---|---|---|
| prod | 10.0.0.0/12 | /20 per account |
| dev/staging | 10.8.0.0/13 | /20 per account |

Mark the CIDR as "reserved" with the workload domain name and date.

### Step 2: Add Account to Terraform

In `environments/prod/aws.tfvars` (or non-prod equivalent), add the new account to the `workload_accounts` map:

```hcl
workload_accounts = {
  # ... existing accounts ...
  "new-domain-prod" = {
    email          = "aws-new-domain-prod@company.com"
    name           = "company-energy-new-domain-prod"
    ou             = "prod"           # or "nonprod"
    workload_domain = "new-domain"
    cost_centre    = "CC-1234"
    vpc_cidr       = "10.0.64.0/20"  # From IPAM reservation above
  }
}
```

### Step 3: Apply Terraform

```bash
cd environments/prod
terraform plan -var-file="prod.tfvars" -target="module.aws_landing_zone.aws_organizations_account.workloads"
# Review plan carefully — account creation cannot be undone without AWS Support
terraform apply -var-file="prod.tfvars" -target="module.aws_landing_zone.aws_organizations_account.workloads"
```

> ⚠️ **Note:** AWS account deletion requires AWS Support and takes 90 days. Always review the plan before applying.

### Step 4: Verify Account Baseline

After account creation, verify the following are in place (automated via Control Tower, but confirm):

```bash
# Verify CloudTrail is enabled
aws cloudtrail describe-trails --include-shadow-trails false \
  --profile new-account-admin \
  --region eu-west-1

# Verify GuardDuty is enrolled
aws guardduty list-detectors \
  --profile new-account-admin \
  --region eu-west-1

# Verify Config recorder is running
aws configservice describe-configuration-recorders \
  --profile new-account-admin \
  --region eu-west-1
```

All three should return active results. If any are missing, check Control Tower enrollment status.

### Step 5: Attach VPC to Transit Gateway

```bash
# In the new account context
cd modules/aws/networking
terraform apply \
  -var="environment=prod" \
  -var="account_vpc_cidr=10.0.64.0/20" \
  -var="tgw_id=$(terraform output -raw tgw_id)" \
  -var="tgw_route_table_id=$(terraform output -raw prod_rt_id)"
```

### Step 6: Update IAM Identity Center

Add the new account to the IAM Identity Center permission set assignments:

1. In the AWS Console → IAM Identity Center → AWS accounts
2. Find the new account
3. Assign the standard permission sets: `PlatformReadOnly`, `WorkloadDeveloper`, `WorkloadAdmin`
4. Map to the appropriate Azure AD groups (naming convention: `aws-{account-name}-{permission-set}`)

### Step 7: Verify network connectivity

```bash
# From an EC2 instance in the new account
# Test connectivity to shared services DNS
nslookup internal.company.com 10.48.0.2

# Test connectivity to on-premises (if required)
ping 172.16.10.1  # On-prem gateway

# Confirm no direct internet (should fail — all egress goes via inspection VPC)
curl --max-time 10 https://ifconfig.me  # Should timeout or be blocked
```

---

## Azure Subscription Vending

### Step 1: Create Subscription

Azure subscription creation requires EA Portal or MCA billing access. Platform admin creates the subscription manually (subscription creation is not yet in Terraform due to EA Portal API limitations):

1. Log into EA Portal / MCA billing account
2. Create subscription with naming convention: `sub-{company}-{domain}-{env}`
3. Note the subscription ID

### Step 2: Add to Terraform

```hcl
# environments/prod/azure.tfvars
workload_subscriptions = {
  "new-domain-prod" = {
    subscription_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    management_group = "production"
    workload_domain  = "new-domain"
    cost_centre      = "CC-1234"
    vnet_cidr        = "10.16.64.0/20"
  }
}
```

### Step 3: Apply Policy Assignments

```bash
cd environments/prod
terraform apply -var-file="azure.tfvars" \
  -target="module.azure_landing_zone" \
  -target="module.azure_networking.azurerm_virtual_hub_connection.spokes"
```

### Step 4: Verify Policy Compliance

After subscription onboarding, check compliance in Azure Policy:

```bash
az policy state summarize \
  --subscription "new-subscription-id" \
  --query "results.policyAssignments[?!compliantCount==totalCount]"
```

Any non-compliant resources created before policies were applied need remediation tasks.

### Step 5: Enable Defender for Cloud

```bash
az security pricing create \
  --name VirtualMachines \
  --tier Standard \
  --subscription "new-subscription-id"

az security pricing create \
  --name SqlServers \
  --tier Standard \
  --subscription "new-subscription-id"

az security pricing create \
  --name StorageAccounts \
  --tier Standard \
  --subscription "new-subscription-id"
```

---

## Post-Onboarding Checklist

- [ ] CIDR reservation updated from "reserved" to "active" in IPAM
- [ ] Account/subscription added to internal asset inventory
- [ ] Cost allocation tags verified
- [ ] On-call rotation updated if prod account
- [ ] Workload team notified with account ID and access instructions
- [ ] Architecture team wiki updated

---

## Rollback

If account vending fails mid-process:

**AWS:** Remove the account entry from `aws.tfvars` and `terraform apply`. The account will be in a detached state. Raise an AWS Support ticket to request account closure.

**Azure:** Remove the subscription entry and `terraform apply`. Detach subscription from Management Group via portal. Cancel subscription via billing portal if not needed.

---

## Escalation

If you encounter issues not covered here, escalate to:

1. Platform Engineering on-call (PagerDuty)
2. AWS TAM (for account vending failures)
3. Azure Customer Success (for EA Portal issues)
