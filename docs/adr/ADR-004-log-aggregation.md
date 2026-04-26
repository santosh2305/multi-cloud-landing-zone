# ADR-004: Centralised vs Federated Log Aggregation

**Date:** 2024-04-10  
**Status:** Accepted  
**Deciders:** Platform Architecture Team  
**Consulted:** Security Operations, Compliance, FinOps  

---

## Context

With workloads spread across multiple AWS accounts and Azure subscriptions, we needed a log aggregation strategy that satisfies:

- SOC monitoring requirements (single pane for threat detection)
- Regulatory retention (energy sector: 7 years for operational logs, 3 years for access logs)
- Cost control (log volume at scale is expensive if poorly managed)
- Tamper evidence (logs must be immutable and independently stored from the workload that generated them)

---

## Decision

**Centralised aggregation with in-cloud-provider isolation.**

- AWS: All CloudTrail, Config, VPC Flow Logs, and GuardDuty findings aggregate to a dedicated Log Archive account. S3 bucket with Object Lock (WORM). Security Hub aggregates findings.
- Azure: All Activity Logs, Diagnostic Settings, and Defender alerts aggregate to a dedicated Log Analytics Workspace in a Security subscription. Immutable storage in Azure Blob with retention lock.
- Cross-cloud SIEM: Microsoft Sentinel as the primary SIEM, with AWS connector pulling GuardDuty + Security Hub findings.

---

## Rationale

Workload accounts are explicitly denied the ability to modify or delete the centralised log buckets via SCP. This means a compromised workload account cannot cover its tracks by deleting logs — a key requirement for forensic integrity.

Sentinel was chosen over a third-party SIEM because the organisation already has Microsoft 365 E5 licences which include Sentinel capacity. AWS Security Hub → Sentinel via the native connector provides unified threat visibility without double-ingestion costs.

---

## Consequences

- Log Archive account/subscription must be bootstrapped before any workload accounts
- Estimated log volume at steady state: ~500GB/month. Costed at ~$200/month in S3 Intelligent-Tiering + Glacier for compliance retention.
- CloudWatch Logs in workload accounts are NOT forwarded centrally (cost control). Only CloudTrail, Config, and GuardDuty findings are centralised. Application logs remain in workload accounts.

---

# ADR-005: Data Residency Enforcement Strategy

**Date:** 2024-04-15  
**Status:** Accepted  
**Deciders:** Platform Architecture Team  
**Consulted:** Legal, Compliance, Data Engineering  

---

## Context

EU energy regulations and GDPR require that certain categories of data — including customer metering data and personally identifiable operational data — remain within the EU. The organisation operates primarily in the EU but has workloads that could inadvertently replicate data to non-EU regions if not constrained.

---

## Decision

**Deny-by-default region policy enforced at the organisational level.**

- AWS: SCP attached to the root OU denies all actions where `aws:RequestedRegion` is not in the approved list (eu-west-1, eu-central-1, eu-west-2)
- Azure: Azure Policy initiative assigned at root Management Group denies resource creation outside approved regions (westeurope, northeurope, uksouth)
- Exception process: Workloads requiring non-EU regions (e.g., a global CDN) must be in a dedicated OU/Management Group with explicit exception Policy

---

## Approved Regions

| Cloud | Region | Use Case |
|---|---|---|
| AWS | eu-west-1 (Ireland) | Primary |
| AWS | eu-central-1 (Frankfurt) | DR / data residency for DE workloads |
| AWS | eu-west-2 (London) | UK-specific workloads post-Brexit |
| Azure | West Europe (Netherlands) | Primary |
| Azure | North Europe (Ireland) | DR |
| Azure | UK South (London) | UK-specific workloads |

---

## Rationale

Tagging-based enforcement was evaluated and rejected. Tags can be omitted or misconfigured. A hard deny at the SCP/Policy level means non-compliant deployments fail at the API level — there is no remediation step required, the control is preventative rather than detective.

---

## Consequences

- Terraform must explicitly specify `provider` blocks with region constraints
- Any new approved region requires an SCP/Policy update — this is intentional friction to prevent accidental expansion
- Global services (IAM, Route53, Azure AD) are exempt from region constraints as they have no data residency implication
