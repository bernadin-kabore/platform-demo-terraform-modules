# ---------------------------------------------------------------------------
# The vending machine itself: one file in the requesting repository's language
# becomes one AWS role, federated to exactly that GitHub repository.
#
# Nothing here reads a long-lived credential, and nothing vends one. The role
# is assumed at runtime by the repository's own workflow, against a token
# GitHub mints for that workflow and no other.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "trust" {
  for_each = var.roles

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Two forms, because GitHub issues two. The classic subject names the
      # owner and repository as strings; the immutable subject appends numeric
      # IDs to each -- repo:owner@136675538/name@1355406331:ref:... -- so that
      # a rename cannot silently transfer a role's trust to whoever claims the
      # freed name. Which one a repository emits is a GitHub-side setting
      # (GET /repos/{owner}/{repo}/actions/oidc/customization/sub), not
      # something this configuration controls, and it can change under a
      # working pipeline. Matching only the classic form produces exactly
      # "Not authorized to perform sts:AssumeRoleWithWebIdentity" against a
      # trust policy that looks correct in every field.
      #
      # The wildcards cover only the ID suffixes. Owner, repository and ref
      # stay pinned, so this is no weaker than one exact string -- a different
      # repository still cannot match.
      values = [
        "repo:${each.value.github_owner}/${each.value.github_repo}:ref:refs/heads/main",
        "repo:${each.value.github_owner}@*/${each.value.github_repo}@*:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "vended" {
  for_each = var.roles

  name               = "${var.name_prefix}-${each.key}-ci"
  assume_role_policy = data.aws_iam_policy_document.trust[each.key].json

  # The whole reason a directory of files can be self-service. Terraform sets
  # this on every vended role unconditionally -- it is not a field the
  # requesting file can express, so no declaration can opt out of it, and the
  # IAM policy on the vending pipeline refuses a CreateRole that omits it.
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(var.tags, {
    VendedFor = "${each.value.github_owner}/${each.value.github_repo}"
  })
}

data "aws_iam_policy_document" "granted" {
  for_each = local.roles_with_statements

  dynamic "statement" {
    for_each = each.value
    content {
      sid       = statement.value.sid
      effect    = "Allow"
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "granted" {
  for_each = local.roles_with_statements

  name   = "vended-grants"
  role   = aws_iam_role.vended[each.key].id
  policy = data.aws_iam_policy_document.granted[each.key].json
}
