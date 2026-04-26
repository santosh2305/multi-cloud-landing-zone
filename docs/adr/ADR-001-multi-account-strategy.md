# ADR-001: Multi-Account vs Single-Account Strategy

**Date:** 2024-03-12  
**Status:** Accepted  
**Deciders:** Platform Architecture Team  
**Consulted:** Security, FinOps, Compliance  

---

## Context

When establishing a cloud foundation for an energy sector organisation operating across AWS and Azure, we needed to decide how to structure the account/subscription hierarchy. The organisation has:

- 3 environments (dev, staging, prod)
- 4 workload domains (generation, grid, retail, corporate)
- Strict regulatory requirements under EU energy law (GDPR + sector-specific)
- An existing on-premises AD environment being migrated to Azure AD
- A FinOps requirement to showback costs by workload domain

The primary options evaluated were:

1. **Single account with resource-level isolation** (tags, IAM boundaries, VPC separation)
2. **Multi-account per environment** (one account per env, all workloads inside)
3. **Multi-account per workload domain + environment** (fully decomposed)

---

## Decision

**Option 3: Multi-account per workload domain per environment.**

Each workload domain gets a dedicated AWS account and Azure subscription per environment. Shared services (DNS, logging, security tooling) live in dedicated accounts/subscriptions per cloud provider.

---

## Rationale

### Why not single-account?

Single-account isolation relies entirely on IAM policies and resource tagging being correct at all times. In practice:

- A misconfigured IAM policy can expose prod resources from a dev context — no hard boundary
- CloudTrail and Cost Explorer cannot separate costs cleanly without extensive tagging discipline (which degrades over time)
- Service quota limits are shared — a runaway dev workload can throttle prod
- Compliance auditors in the energy sector have started explicitly requiring account-level isolation for production systems handling metering data

### Why not multi-account per environment only?

Per-environment accounts (dev/staging/prod) provide blast radius isolation between environments but not between workload domains within an environment. A compromised retail application in prod still has network adjacency to generation control data in prod. The threat model for energy companies requires defence-in-depth at the workload domain level.

### Why option 3?

- **Blast radius**: A security incident in the retail domain cannot laterally reach generation or grid workloads
- **Compliance**: Metering data (generation domain) can be subject to stricter controls — dedicated accounts allow applying tighter SCPs/Policies without affecting other domains
- **Cost attribution**: Native per-account billing provides clean showback without tagging dependency
- **IAM simplicity**: Cross-account access is explicit and auditable; no risk of overly permissive policies leaking between domains
- **Quota isolation**: Each account has independent service quotas

### Trade-offs accepted

| Trade-off | Mitigation |
|---|---|
| Higher operational overhead (more accounts to manage) | AWS Control Tower + Terraform module standardisation |
| More complex cross-domain networking | Transit Gateway hub-and-spoke with explicit route policies |
| Identity sprawl risk | Centralised identity via Azure AD → AWS IAM Identity Center federation |
| More Terraform state files to manage | Remote state in S3/Azure Blob with consistent naming convention |

---

## Consequences

- We will use AWS Organizations with SCPs to enforce guardrails at the OU level
- Azure Management Group hierarchy mirrors the AWS OU structure for consistency
- Account/subscription vending is automated via Terraform to keep provisioning time under 30 minutes
- A dedicated security audit account on each cloud aggregates all logs — workload accounts cannot disable or modify logging

---

## Alternatives Considered and Rejected

**Option 1 (single account):** Rejected. Insufficient blast radius isolation for regulated workloads. Compliance team flagged this as a risk that would require compensating controls exceeding the cost of the multi-account approach.

**Option 2 (per-environment only):** Rejected. Does not address lateral movement risk within prod environment across workload domains.
