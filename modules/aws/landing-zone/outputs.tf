# modules/aws/landing-zone/outputs.tf

output "security_ou_id" {
  description = "ID of the Security OU. Use this to attach accounts for log archive and security tooling."
  value       = aws_organizations_organizational_unit.security.id
}

output "shared_services_ou_id" {
  description = "ID of the Shared Services OU."
  value       = aws_organizations_organizational_unit.shared_services.id
}

output "workloads_prod_ou_id" {
  description = "ID of the Production workloads OU."
  value       = aws_organizations_organizational_unit.workloads_prod.id
}

output "workloads_nonprod_ou_id" {
  description = "ID of the Non-Production workloads OU."
  value       = aws_organizations_organizational_unit.workloads_nonprod.id
}

output "global_workloads_ou_id" {
  description = "ID of the Global Workloads exception OU. Requires CISO approval before use."
  value       = aws_organizations_organizational_unit.global_workloads.id
}

output "deny_regions_scp_id" {
  description = "ID of the region deny SCP. Reference this when validating policy attachments."
  value       = aws_organizations_policy.deny_non_eu_regions.id
}
