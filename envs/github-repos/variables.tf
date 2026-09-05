variable "github_org" {
  description = "GitHub org (or user) that owns every repo in var.repositories"
  type        = string
}

variable "repositories" {
  description = "Repos to apply branch protection to. Start with the 5 platform repos; add a service repo name here once it exists (see README for the alternative: driving this list from platform-demo-gitops/services/*/config.json instead of hand-maintaining it)."
  type        = list(string)
  default = [
    "platform-demo-terraform-modules",
    "platform-demo-gitops",
    "platform-demo-backstage",
    "platform-demo-hello-world-template",
    # The AI Platform Agent opens pull requests against the four repos above.
    # It is protected on the same terms as they are, which is what makes
    # "human approval" a real gate rather than a diagram box: the agent's App
    # appears in no bypass_actors list anywhere, so it can propose and it can
    # never merge — including into its own repository.
    "platform-demo-ai-agent",
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

    Note that platform-demo-ai-agent's ci.yml also runs an "evals" job, which
    is not listed here because this list applies to every repository uniformly
    and no other repository has one. Its enforcement comes from being a
    required dependency of that repository's build-scan-sign job: an image is
    never built, so never signed, so never admitted, if the eval suite fails.
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

variable "deploy_bot_app_id" {
  description = <<-EOT
    Numeric GitHub App ID of "platform-deploy-bot" — only used by
    organization-ruleset.tf.example (see that file and this module's
    README). Unused while these repos are on a personal account; the
    equivalent bypass is configured via app-config.yaml's
    platform.deployBotAppId instead, read by the
    platform:github:branch-protection scaffolder action.
  EOT
  type        = number
  default     = null
}
