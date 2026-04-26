# Multi-Cloud Landing Zone — AWS & Azure

A production-ready, architecture-driven landing zone for regulated energy sector workloads across AWS and Azure. This repository provides Terraform modules, Architecture Decision Records (ADRs), and operational runbooks for establishing a secure, compliant, and observable multi-cloud foundation.

---

## Why This Exists

Energy companies operating across multiple cloud providers face a specific set of challenges that generic landing zone templates don't address:

- **Data residency requirements** — regulatory constraints on where operational and metering data can reside
- **OT/IT boundary enforcement** — clear network segmentation between operational technology networks and cloud workloads
- **Cost governance at scale** — energy workloads often have unpredictable burst patterns (weather events, outages) requiring guardrails
- **Dual-cloud resilience** — some workloads require active-active or active-passive across AWS and Azure due to vendor SLA gaps for critical infrastructure

This landing zone was designed with those constraints in mind, not as an afterthought.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     Management Plane                            │
│  ┌──────────────┐              ┌──────────────────────────────┐ │
│  │  AWS Control │              │  Azure Management Group      │ │
│  │  Tower / Org │              │  Hierarchy                   │ │
│  └──────┬───────┘              └──────────────┬───────────────┘ │
│         │                                     │                 │
│  ┌──────▼──────────────────────────────────────▼─────────────┐  │
│  │              Centralised Identity (Azure AD / AWS SSO)    │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                     Connectivity Layer                          │
│                                                                 │
│  AWS Transit Gateway ◄──── Site-to-Site VPN / ExpressRoute ────►│
│  (Hub VPC)                                                Azure  │
│                                                        vWAN Hub  │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────────────┐    ┌──────────────────────────────────┐
│         AWS              │    │             Azure                 │
│                          │    │                                   │
│  ┌────────────────────┐  │    │  ┌───────────────────────────┐   │
│  │  Shared Services   │  │    │  │  Shared Services          │   │
│  │  (DNS, Logging,    │  │    │  │  (DNS, Logging,           │   │
│  │   Monitoring)      │  │    │  │   Monitoring)             │   │
│  └────────────────────┘  │    │  └───────────────────────────┘   │
│                          │    │                                   │
│  ┌────────────────────┐  │    │  ┌───────────────────────────┐   │
│  │  Workload Accounts │  │    │  │  Workload Subscriptions   │   │
│  │  (Dev/Staging/Prod)│  │    │  │  (Dev/Staging/Prod)       │   │
│  └────────────────────┘  │    │  └───────────────────────────┘   │
│                          │    │                                   │
│  ┌────────────────────┐  │    │  ┌───────────────────────────┐   │
│  │  Security/Audit    │  │    │  │  Security/Audit           │   │
│  │  Account           │  │    │  │  Subscription             │   │
│  └────────────────────┘  │    │  └───────────────────────────┘   │
└──────────────────────────┘    └──────────────────────────────────┘
```

---

## Repository Structure

```
.
├── docs/
│   ├── adr/                    # Architecture Decision Records
│   ├── diagrams/               # Architecture diagrams (Mermaid + draw.io)
│   └── runbooks/               # Operational runbooks
├── modules/
│   ├── aws/
│   │   ├── landing-zone/       # AWS Organizations, Control Tower bootstrap
│   │   ├── networking/         # Transit Gateway, VPCs, PrivateLink
│   │   ├── security/           # SCPs, GuardDuty, Security Hub, IAM
│   │   └── logging/            # CloudTrail, Config, centralised S3
│   └── azure/
│       ├── landing-zone/       # Management Groups, Policy, Subscriptions
│       ├── networking/         # vWAN, VNets, Private Endpoints
│       ├── security/           # Defender for Cloud, Policies, RBAC
│       └── logging/            # Diagnostic settings, Log Analytics, Sentinel
├── environments/
│   ├── dev/
│   ├── staging/
│   └── prod/
├── scripts/                    # Bootstrap and utility scripts
└── .github/workflows/          # CI/CD pipelines
```

---

## Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Multi-account/subscription strategy | Separate accounts per environment | Blast radius isolation; independent IAM boundaries |
| Transit connectivity | AWS Transit Gateway + Azure vWAN | Hub-and-spoke scales better than full mesh for 20+ VNets/VPCs |
| Identity federation | Azure AD as IdP → AWS IAM Identity Center | Single pane; energy sector often Azure AD-heavy from M365 |
| Log aggregation | Dual SIEM with cross-feed | Regulatory requirement; some audits require in-cloud-provider logs |
| Data residency | Region locking via SCP/Policy | EU energy regulation; explicit deny on non-compliant regions |

Full rationale in [docs/adr/](docs/adr/).

---

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI >= 2.x with Organizations admin access
- Azure CLI >= 2.50 with Owner on root Management Group
- An existing Azure AD tenant (used as IdP for both clouds)

---

## Getting Started

### 1. Bootstrap AWS Organizations

```bash
cd scripts/
./bootstrap-aws-org.sh --profile master-account
```

### 2. Initialise Terraform backend

```bash
cd environments/prod
terraform init \
  -backend-config="bucket=your-tfstate-bucket" \
  -backend-config="key=landing-zone/prod/terraform.tfstate"
```

### 3. Deploy shared modules

```bash
# AWS
terraform -chdir=modules/aws/landing-zone apply -var-file=../../environments/prod/aws.tfvars

# Azure
terraform -chdir=modules/azure/landing-zone apply -var-file=../../environments/prod/azure.tfvars
```

---

## Security Posture

| Control | AWS | Azure |
|---|---|---|
| MFA enforcement | IAM Identity Center MFA policy | Conditional Access |
| Privileged access | AWS SSO with time-limited sessions | Azure PIM |
| Threat detection | GuardDuty + Security Hub | Defender for Cloud |
| Policy guardrails | Service Control Policies (SCPs) | Azure Policy + Initiatives |
| Audit logging | CloudTrail (org-wide) + Config | Activity Log + Diagnostic Settings |
| Secret management | AWS Secrets Manager | Azure Key Vault |

---

## ADR Index

| # | Title | Status |
|---|---|---|
| [ADR-001](docs/adr/ADR-001-multi-account-strategy.md) | Multi-account vs single-account strategy | Accepted |
| [ADR-002](docs/adr/ADR-002-identity-federation.md) | Identity federation approach | Accepted |
| [ADR-003](docs/adr/ADR-003-network-topology.md) | Hub-and-spoke vs full mesh networking | Accepted |
| [ADR-004](docs/adr/ADR-004-log-aggregation.md) | Centralised vs federated log aggregation | Accepted |
| [ADR-005](docs/adr/ADR-005-data-residency.md) | Data residency enforcement strategy | Accepted |

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). All changes to `prod` environment require two approvals and a passing `terraform plan` in CI.

---

## Licence

MIT
