output "protected_branches" {
  description = "repo:pattern pairs currently under branch protection"
  value       = keys(github_branch_protection.this)
}
