# Contributing

## Branch Strategy

- `main` — protected. No direct pushes. All changes via PR.
- `feature/*` — feature branches. Short-lived.
- `fix/*` — bug fixes.

## PR Requirements

- All PRs require passing CI (fmt, validate, tfsec)
- Non-prod changes: 1 approval required
- Production changes: 2 approvals required, including Platform Architecture lead
- PR description must reference the relevant ADR if introducing a new architectural pattern

## Terraform Guidelines

- Run `terraform fmt -recursive` before committing
- All new variables must have a `description`
- Sensitive variables must be marked `sensitive = true`
- New modules must include a `README.md` with inputs/outputs table
- Do not hardcode account IDs or subscription IDs — use variables

## Adding a New Module

1. Create the module directory under `modules/aws/` or `modules/azure/`
2. Add `main.tf`, `variables.tf`, `outputs.tf`
3. Add a `README.md` with purpose, inputs, outputs, and example usage
4. Wire the module into the appropriate `environments/*/main.tf`
5. Update this repo's root `README.md` structure diagram if needed

## ADR Process

Significant architectural changes require an ADR:

1. Copy `docs/adr/template.md`
2. Fill in context, decision, rationale, consequences
3. Submit as part of the PR introducing the change
4. ADR status starts as "Proposed" → moves to "Accepted" on PR merge

Changes that require an ADR:
- New module introducing a net-new service
- Changes to network topology
- Changes to IAM/identity patterns
- Changes to logging or security controls
- Changes to approved region list

## Commit Message Format

```
<type>(<scope>): <short description>

[optional body]
[optional footer]
```

Types: `feat`, `fix`, `docs`, `refactor`, `chore`  
Scope: `aws/networking`, `azure/security`, `environments/prod`, `docs`, etc.

Examples:
```
feat(aws/security): add Config rule for EBS encryption
fix(azure/networking): correct vWAN hub CIDR overlap with on-premises
docs(adr): add ADR-006 for secret management strategy
```
