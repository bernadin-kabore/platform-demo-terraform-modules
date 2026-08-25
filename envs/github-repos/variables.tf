variable "github_org" {
  description = "GitHub org (or user) that owns every repo in var.repositories"
  type        = string
}

variable "repositories" {
  description = "Repos to apply branch protection to. Start with the 4 platform repos; add a service repo name here once it exists (see README for the alternative: driving this list from platform-demo-gitops/services/*/config.json instead of hand-maintaining it)."
  type        = list(string)
  default = [
    "platform-demo-terraform-modules",
    "platform-demo-gitops",
    "platform-demo-backstage",
    "platform-demo-hello-world-template",
  ]
}

variable "protected_branch_patterns" {
  description = "Branch name patterns to protect on every repo above"
  type        = list(string)
  default     = ["main", "develop", "release/*"]
}

variable "required_status_check_contexts" {
  description = <<-EOT
    Status check context names that must pass before merging. "coverage / check"
    is the context GitHub derives from the `coverage` job in each service's
    ci.yml calling code-coverage.yml's `check` job — see
    platform-demo-hello-world-template/.github/workflows/code-coverage.yml.
    test/sast/sca are the ci.yml jobs of the same name.
  EOT
  type        = list(string)
  default     = ["test", "sast", "sca", "coverage / check"]
}

variable "required_approving_review_count" {
  type    = number
  default = 1
}

variable "enforce_admins" {
  description = "Whether repo admins are also bound by these rules (no bypassing via admin override)"
  type        = bool
  default     = true
}
