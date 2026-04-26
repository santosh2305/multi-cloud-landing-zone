# ADR-005: Data Residency Enforcement Strategy

**Date:** 2024-04-15  
**Status:** Accepted  
**Deciders:** Platform Architecture Team  
**Consulted:** Legal, Compliance, Data Engineering  

---

## Context

EU energy regulations and GDPR require that certain categories of data — including customer metering data and personally identifiable operational data — remain within the EU. The organisation operates primarily in the EU but has workloads that could inadvertently replicate data to non-EU regions if not constrained.

The specific risk scenarios identified:

1. A developer deploys an S3 replication rule to us-east-1 for convenience
2. A data pipeline accidentally writes to a globally-replicated database without region constraints
3. A new team spins up infrastructure in ap-southeast-1 for testing and forgets to clean it up
4. Cross-region disaster recovery is configured to a non-EU region

---

## Decision

**Deny-by-default region policy enforced at the organisational level via preventative controls.**

- **AWS:** SCP attached to the root OU explicitly denies all API actions where `aws:RequestedRegion` is not in the approved EU list
- **Azure:** Azure Policy initiative at root Management Group denies resource creation outside approved regions; enforced via `deny` effect (not `audit`)
- **Exception path:** Workloads with legitimate non-EU requirements are moved to a dedicated OU (`GlobalWorkloads`) with a separate SCP that permits specific regions. Requires CISO approval.

---

## Approved Regions

| Cloud | Region | Code | Primary Use |
|---|---|---|---|
| AWS | Ireland | eu-west-1 | Primary region |
| AWS | Frankfurt | eu-central-1 | DR + DE data residency |
| AWS | London | eu-west-2 | UK-specific workloads |
| Azure | Netherlands | westeurope | Primary region |
| Azure | Ireland | northeurope | DR |
| Azure | London | uksouth | UK-specific workloads |

---

## Enforcement Implementation

### AWS SCP (excerpt)

```json
{
  "Sid": "DenyNonApprovedRegions",
  "Effect": "Deny",
  "NotAction": [
    "iam:*",
    "organizations:*",
    "route53:*",
    "budgets:*",
    "cloudfront:*",
    "sts:*",
    "support:*",
    "trustedadvisor:*"
  ],
  "Resource": "*",
  "Condition": {
    "StringNotIn": {
      "aws:RequestedRegion": [
        "eu-west-1",
        "eu-central-1",
        "eu-west-2"
      ]
    }
  }
}
```

### Azure Policy (excerpt)

```json
{
  "if": {
    "not": {
      "field": "location",
      "in": ["westeurope", "northeurope", "uksouth", "global"]
    }
  },
  "then": {
    "effect": "deny"
  }
}
```

---

## Rationale

### Why preventative rather than detective?

Detective controls (Config rules, Azure Policy in `audit` mode) generate alerts after a non-compliant resource already exists. In a regulated environment, the cost of a compliance incident (notification obligations, audit findings) exceeds the cost of occasionally blocking a legitimate deployment that requires an exception process.

Preventative controls fail fast and force the correct conversation to happen before deployment, not after.

### Why SCP at root OU, not per-OU?

Applying at root OU means the control cannot be bypassed by moving an account to a different OU without explicit CISO approval. If the control were applied per-OU, an account could temporarily be moved to an unrestricted OU.

### Global services exemption

Services like IAM, Route53, CloudFront, and Azure AD operate globally and do not store data in specific regions in the traditional sense. These are explicitly excluded from the region deny to avoid breaking global service functionality.

---

## Consequences

- Any Terraform module that does not specify `provider` with an explicit region will fail deployment if the default region is outside the approved list
- The exception process adds 2–5 business days for non-EU deployments — teams must plan accordingly
- Terraform CI/CD pipeline includes a pre-plan check that validates all provider blocks reference approved regions
- This control is reviewed annually by the compliance team and updated if the approved region list changes

---

## Alternatives Considered and Rejected

**Tagging-based enforcement:** Rejected. Tags can be omitted or misconfigured. Preventative controls at the API level are more robust.

**Audit-mode policy only:** Rejected. Does not prevent non-compliant deployments; only reports them. Insufficient for regulatory requirements.

**Per-service enforcement:** Evaluated for services with explicit data storage (S3, RDS, Azure Storage). Rejected as incomplete — it would miss services that indirectly store data (e.g., CloudWatch Logs, Lambda environment variables).
