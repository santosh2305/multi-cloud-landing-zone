# ADR-002: Identity Federation Approach

**Date:** 2024-03-18  
**Status:** Accepted  
**Deciders:** Platform Architecture Team  
**Consulted:** Security, IAM, Active Directory Team  

---

## Context

The organisation already has Azure Active Directory as its corporate IdP, used for M365, on-premises application SSO, and conditional access policies. We needed to determine how to handle identity across both AWS and Azure cloud environments without creating a second identity silo.

Key requirements:
- Single MFA prompt regardless of which cloud a user is accessing
- Privileged access must be time-limited and auditable
- Break-glass accounts must exist but be tightly controlled
- Service-to-service identity must not use long-lived static credentials

---

## Decision

**Azure AD as the single IdP, federated into AWS IAM Identity Center (formerly SSO).**

- Human identity: Azure AD → AWS IAM Identity Center (SAML 2.0 federation)
- Workload identity (AWS): IAM Roles with OIDC for CI/CD; instance profiles for compute
- Workload identity (Azure): Managed Identities exclusively; no service principal secrets
- Privileged access: Azure PIM for Azure resources; AWS Permission Sets with session duration limits for AWS

---

## Rationale

### Why Azure AD as the single IdP?

The organisation has 4,000+ users already in Azure AD with mature conditional access policies, including device compliance checks required for energy sector regulatory compliance. Building a parallel identity system in AWS (Cognito or native IAM users) would:

- Create a second MFA enrolment burden for users
- Duplicate joiner/mover/leaver processes, increasing the window where stale access exists
- Require maintaining two separate conditional access policy sets
- Undermine the existing SOC monitoring which is tuned to Azure AD sign-in signals

### Why AWS IAM Identity Center over direct SAML on each account?

Direct SAML federation to individual AWS accounts was the legacy approach. IAM Identity Center provides:

- Central permission set management — change a permission set once, it propagates to all assigned accounts
- Centralised access audit in a single location rather than per-account CloudTrail
- Automated account assignment via Terraform without per-account manual SAML config

### Why Managed Identities over service principal secrets on Azure?

Service principal secrets are a major source of credential leaks. Managed Identities eliminate the secret entirely — the platform handles token issuance and rotation. For the energy sector threat model, eliminating static credentials from workload identity is a non-negotiable control.

### Why OIDC for AWS CI/CD over long-lived IAM access keys?

GitHub Actions (and equivalent CI systems) support OIDC token exchange with AWS STS. This means:

- No AWS access keys stored in CI/CD secrets vaults
- Tokens are scoped to the job and expire after the pipeline run
- Audit trail shows exactly which pipeline run assumed which role

---

## Consequences

- Azure AD must be treated as a critical dependency — its availability affects AWS access
- Break-glass procedure must include a path that doesn't require Azure AD (local IAM emergency user per account, credentials sealed in physical vault)
- Azure AD group naming convention must be agreed upfront — groups drive AWS Permission Set assignments
- AWS IAM Identity Center must be provisioned in the management account only

---

## Break-Glass Procedure

Each AWS account will have one break-glass IAM user with console + programmatic access. Credentials are:

1. Generated at account creation
2. Encrypted with the Security team's GPG key
3. Stored in physical sealed envelope in the data centre
4. Access to these credentials triggers a CloudWatch alarm and PagerDuty alert

Break-glass use must be documented in the incident log within 1 hour of use.

---

## Alternatives Considered and Rejected

**AWS IAM Identity Center as IdP (native users):** Rejected. Duplicates the identity system; does not leverage existing Azure AD conditional access investment.

**Okta as neutral IdP:** Evaluated. Would provide vendor neutrality but adds cost and another dependency. The organisation is heavily Azure-invested and the risk of Azure AD being the single IdP is accepted given existing DR plans.

**Per-account SAML federation:** Rejected. Operationally unmaintainable at scale; IAM Identity Center is the current AWS-recommended approach.
