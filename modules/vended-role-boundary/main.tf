# ---------------------------------------------------------------------------
# The ceiling every vended role is capped at.
#
# This lives in its own module, instantiated by envs/dev, and NOT in the role
# vending machine -- deliberately. If the vending machine created its own
# boundary, the pipeline that vends roles would also own the document capping
# them, and could raise its own ceiling in the same commit that used it. The
# platform team owns this; the vending machine is handed the ARN and can only
# attach it.
#
# A permissions boundary is not a grant. It is the upper bound on what an
# identity policy attached to the role can ever take effect for: the role's
# effective permissions are the intersection of the two. That is what makes a
# vending machine safe to point at a directory of files -- a mistaken or
# malicious policy merged into exceptions/ still cannot exceed this document,
# so review is a second line of defence rather than the only one.
#
# The Allow set is therefore the whole list of service namespaces this platform
# is willing to vend. Adding a service here is a deliberate platform-team
# decision and the point at which someone should think about blast radius;
# adding a bundle that uses an already-allowed namespace is not.
#
# The Deny statements below are redundant against that Allow set -- iam: is not
# in it, so it is already outside the ceiling. They are written anyway so that
# widening the Allow set later cannot silently re-open privilege escalation.
# ---------------------------------------------------------------------------

locals {
  # Regional services the bundles vend. Split out because the region-lock Deny
  # must name exactly these: a Deny keyed on aws:RequestedRegion would also
  # match calls that do not set it, and sts:GetCallerIdentity -- which
  # aws-actions/configure-aws-credentials calls on every run, before any user
  # code -- is one of them. Denying that breaks the pipeline at the login step
  # with an error that points at the credentials, not at this policy.
  regional_vendable_services = ["ecr:*", "s3:*", "sqs:*", "dynamodb:*", "logs:*"]
}

data "aws_iam_policy_document" "boundary" {
  statement {
    sid       = "VendableServiceCeiling"
    effect    = "Allow"
    actions   = local.regional_vendable_services
    resources = ["*"]
  }

  statement {
    sid    = "IdentitySelfInspection"
    effect = "Allow"
    # configure-aws-credentials calls this to confirm the assume-role worked.
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }

  statement {
    sid    = "NoIdentityManagement"
    effect = "Deny"
    # The escalation that matters: a role that can create roles, attach
    # policies, or edit its own boundary is unbounded. Denying the namespace
    # outright also stops iam:PassRole, which no image-publishing pipeline
    # needs and which is the usual bridge to a more privileged identity.
    actions   = ["iam:*", "organizations:*", "account:*"]
    resources = ["*"]
  }

  statement {
    sid    = "NoRoleChaining"
    effect = "Deny"
    # Without this a vended role can assume a role that has no boundary, and
    # the ceiling stops meaning anything one hop later.
    actions = [
      "sts:AssumeRole",
      "sts:AssumeRoleWithSAML",
      "sts:AssumeRoleWithWebIdentity",
      "sts:GetFederationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "NoClusterAccess"
    effect = "Deny"
    # CI publishes artifacts; Argo CD deploys them. A pipeline that can reach
    # the cluster API or start instances collapses that separation, which is
    # the property the signed-image chain depends on.
    actions   = ["eks:*", "ec2:*"]
    resources = ["*"]
  }

  statement {
    sid       = "RegionLock"
    effect    = "Deny"
    actions   = local.regional_vendable_services
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "${var.name_prefix}-vended-role-boundary"
  description = "Upper bound on every role vended by the role vending machine. Attached as a permissions boundary, never as an identity policy."
  policy      = data.aws_iam_policy_document.boundary.json
  tags        = var.tags
}
