data "github_repository" "this" {
  for_each = toset(var.repositories)
  name     = each.value
}

locals {
  # One branch_protection resource per (repo, pattern) pair, e.g.
  # "platform-demo-gitops:release/*" — a repo with no release branches yet
  # still gets the rule; GitHub applies it the moment a matching branch appears.
  protections = {
    for pair in setproduct(var.repositories, var.protected_branch_patterns) :
    "${pair[0]}:${pair[1]}" => { repo = pair[0], pattern = pair[1] }
  }
}

resource "github_branch_protection" "this" {
  for_each = local.protections

  repository_id = data.github_repository.this[each.value.repo].node_id
  pattern       = each.value.pattern

  required_status_checks {
    strict   = true # branch must be up to date with the base branch before merging
    contexts = var.required_status_check_contexts
  }

  required_pull_request_reviews {
    required_approving_review_count = var.required_approving_review_count
    require_code_owner_reviews      = false
    dismiss_stale_reviews           = true
  }

  enforce_admins         = var.enforce_admins
  allows_deletions       = false
  allows_force_pushes    = false
  require_signed_commits = false
}
