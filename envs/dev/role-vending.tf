# ---------------------------------------------------------------------------
# The role vending machine's AWS side, owned here rather than by the vending
# repository itself.
#
# Two things live here and deliberately not in platform-demo-role-vending:
#
#   the boundary  -- the ceiling every vended role is capped at. If the vending
#                    repository owned it, the pipeline that vends roles could
#                    raise its own ceiling in the same commit that used it.
#
#   the CI role   -- the identity that pipeline assumes. It cannot vend itself:
#                    something outside the machine has to create the first
#                    role, and this is that something.
#
# This is the most privileged identity on the platform -- it creates IAM roles.
# What makes that survivable is not that it is carefully reviewed, but that its
# own policy pins iam:PermissionsBoundary to one exact ARN. A CreateRole call
# that omits the boundary, or names a different one, is refused by IAM. The
# vending pipeline is structurally incapable of producing an unbounded role,
# whatever is merged into it.
# ---------------------------------------------------------------------------

module "vended_role_boundary" {
  source      = "../../modules/vended-role-boundary"
  name_prefix = var.cluster_name
  aws_region  = var.aws_region
  tags        = local.tags
}

locals {
  vending_enabled = var.role_vending_repo != null

  vending_state_bucket = local.vending_enabled ? coalesce(
    var.role_vending_repo.state_bucket,
    "platform-demo-tfstate-${data.aws_caller_identity.current.account_id}",
  ) : ""

  # Repositories belonging to the platform's own components. The vending
  # machine may create and delete application repositories freely, but these
  # are owned by this root and it must not be able to remove them.
  platform_service_repository_arns = [
    for name in keys(var.platform_services) :
    "arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/${name}"
  ]

  vended_role_pattern = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.cluster_name}-*-ci"
}

data "aws_iam_policy_document" "role_vending_trust" {
  count = local.vending_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.service_delivery.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Both subject forms, for the same reason as every other CI role here:
      # GitHub may emit the classic or the immutable-ID form, the choice is a
      # repository-side setting, and matching only one produces an
      # authorization failure against a trust policy that reads correctly in
      # every field.
      values = [
        "repo:${var.role_vending_repo.github_owner}/${var.role_vending_repo.name}:ref:refs/heads/main",
        "repo:${var.role_vending_repo.github_owner}@*/${var.role_vending_repo.name}@*:ref:refs/heads/main",
      ]
    }
  }
}

data "aws_iam_policy_document" "role_vending" {
  count = local.vending_enabled ? 1 : 0

  # -- IAM -------------------------------------------------------------------

  statement {
    sid    = "VendRolesOnlyUnderTheBoundary"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:PutRolePermissionsBoundary",
    ]
    resources = [local.vended_role_pattern]

    # The line the whole design rests on. Without the condition this role could
    # create an unbounded role and assume it; with it, IAM itself refuses.
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [module.vended_role_boundary.arn]
    }
  }

  statement {
    sid    = "ManageAlreadyVendedRoles"
    effect = "Allow"
    # No boundary condition here, and none is needed: these actions only reach
    # roles that already exist, and the only way one came to exist is the
    # statement above. Inline policies are capped by the boundary the role
    # already carries.
    actions = [
      "iam:GetRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole",
      "iam:ListRoleTags", "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRolePolicy",
      "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [local.vended_role_pattern]
  }

  statement {
    sid    = "NeverStripOrSwapTheBoundary"
    effect = "Deny"
    # Belt and braces against a future widening of the allow set above.
    # Removing a boundary from an existing role would otherwise be a way to
    # launder one created correctly into one that is not. AttachRolePolicy is
    # denied because the vending machine grants through inline policies only,
    # so a managed-policy attachment could only be something unintended.
    actions   = ["iam:DeleteRolePermissionsBoundary", "iam:AttachRolePolicy"]
    resources = ["*"]
  }

  statement {
    sid    = "ReadTheBoundaryAndTheProvider"
    effect = "Allow"
    # Data sources: the boundary policy it must attach, and the account's
    # GitHub OIDC provider, which envs/dev owns.
    actions = [
      "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions",
      "iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders",
    ]
    resources = ["*"]
  }

  # -- ECR -------------------------------------------------------------------

  statement {
    sid    = "ManageApplicationImageRepositories"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository", "ecr:DeleteRepository",
      "ecr:DescribeRepositories", "ecr:ListTagsForResource",
      "ecr:TagResource", "ecr:UntagResource",
      "ecr:PutLifecyclePolicy", "ecr:GetLifecyclePolicy",
      "ecr:DeleteLifecyclePolicy", "ecr:PutImageScanningConfiguration",
      "ecr:PutImageTagMutability",
    ]
    resources = ["arn:aws:ecr:${var.aws_region}:${data.aws_caller_identity.current.account_id}:repository/*"]
  }

  dynamic "statement" {
    # Only meaningful when this root actually owns some repositories.
    for_each = length(local.platform_service_repository_arns) > 0 ? [1] : []
    content {
      sid    = "NeverTouchPlatformImageRepositories"
      effect = "Deny"
      actions = [
        "ecr:DeleteRepository", "ecr:PutLifecyclePolicy",
        "ecr:DeleteLifecyclePolicy", "ecr:SetRepositoryPolicy",
      ]
      resources = local.platform_service_repository_arns
    }
  }

  statement {
    sid    = "NeverChangeRegistryWideConfiguration"
    effect = "Deny"
    # The scanning configuration is an account-wide singleton owned by
    # modules/ecr-registry from this state. A vending apply that could rewrite
    # it would silently turn off scan-on-push for every repository at once.
    actions = [
      "ecr:PutRegistryScanningConfiguration",
      "ecr:PutReplicationConfiguration",
      "ecr:PutRegistryPolicy",
      "ecr:DeleteRegistryPolicy",
    ]
    resources = ["*"]
  }

  # -- Its own Terraform state ----------------------------------------------

  statement {
    sid       = "StateObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.vending_state_bucket}/${var.role_vending_repo.state_key_prefix}*"]
  }

  statement {
    sid       = "StateBucketListing"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${local.vending_state_bucket}"]
    condition {
      # Listing is bucket-level, so without this the vending pipeline could
      # enumerate every environment's state keys, including envs/dev.
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.role_vending_repo.state_key_prefix}*"]
    }
  }

  statement {
    sid       = "StateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.role_vending_repo.lock_table}"]
  }

  statement {
    sid       = "ConfirmItsOwnIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "role_vending" {
  count = local.vending_enabled ? 1 : 0

  name               = "${var.cluster_name}-role-vending-ci"
  description        = "Assumed by platform-demo-role-vending's pipeline. Can create roles only with the platform's permissions boundary attached."
  assume_role_policy = data.aws_iam_policy_document.role_vending_trust[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy" "role_vending" {
  count = local.vending_enabled ? 1 : 0

  name   = "vend-roles"
  role   = aws_iam_role.role_vending[0].id
  policy = data.aws_iam_policy_document.role_vending[0].json
}

# ---------------------------------------------------------------------------
# A second, read-only identity, for plans on pull requests.
#
# The role above is trusted from refs/heads/main only, which means a pull
# request cannot assume it -- deliberately, since a pull request must never be
# able to apply. But the review model this platform chose depends on a reviewer
# seeing the plan before merging: the human approval was kept precisely because
# it is where a person confirms the change is wanted, and an approval given
# without a plan is a rubber stamp.
#
# So plan and apply are two identities, split by what they are allowed to do
# rather than by trust in the branch alone. This one can read everything the
# refresh touches and write nothing but the state lock.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "role_vending_plan_trust" {
  count = local.vending_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.service_delivery.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # The pull_request subject rather than a branch: a pull request build
      # does not run on a named ref. Note that a workflow triggered by a fork's
      # pull request also presents this subject, so this role is scoped to read
      # and to the state lock, and nothing else.
      values = [
        "repo:${var.role_vending_repo.github_owner}/${var.role_vending_repo.name}:pull_request",
        "repo:${var.role_vending_repo.github_owner}@*/${var.role_vending_repo.name}@*:pull_request",
      ]
    }
  }
}

data "aws_iam_policy_document" "role_vending_plan" {
  count = local.vending_enabled ? 1 : 0

  statement {
    sid    = "ReadEverythingThePlanRefreshes"
    effect = "Allow"
    actions = [
      "iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies", "iam:ListRoleTags",
      "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions",
      "iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders",
      "ecr:DescribeRepositories", "ecr:ListTagsForResource",
      "ecr:GetLifecyclePolicy",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.vending_state_bucket}/${var.role_vending_repo.state_key_prefix}*"]
  }

  statement {
    sid       = "ListOnlyItsOwnStatePrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${local.vending_state_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.role_vending_repo.state_key_prefix}*"]
    }
  }

  statement {
    sid    = "TakeAndReleaseTheStateLock"
    effect = "Allow"
    # A plan locks state like an apply does. Running with -lock=false instead
    # would avoid needing this, at the cost of planning against state another
    # run is mid-write on.
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = ["arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${var.role_vending_repo.lock_table}"]
  }

  statement {
    sid    = "WriteNothingElse"
    effect = "Deny"
    # This role exists to produce a plan. Any mutation reaching AWS from a
    # pull request build would be a bug in the workflow, and this turns that
    # bug into an error instead of a change.
    actions = [
      "iam:Create*", "iam:Delete*", "iam:Put*", "iam:Update*",
      "iam:Attach*", "iam:Detach*", "iam:Tag*", "iam:Untag*",
      "ecr:Create*", "ecr:Delete*", "ecr:Put*", "ecr:Set*",
      "s3:PutObject", "s3:DeleteObject",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "role_vending_plan" {
  count = local.vending_enabled ? 1 : 0

  name               = "${var.cluster_name}-role-vending-plan"
  description        = "Assumed by pull request builds in platform-demo-role-vending. Reads state and AWS to render a plan; can write nothing but the state lock."
  assume_role_policy = data.aws_iam_policy_document.role_vending_plan_trust[0].json
  tags               = local.tags
}

resource "aws_iam_role_policy" "role_vending_plan" {
  count = local.vending_enabled ? 1 : 0

  name   = "plan-only"
  role   = aws_iam_role.role_vending_plan[0].id
  policy = data.aws_iam_policy_document.role_vending_plan[0].json
}
