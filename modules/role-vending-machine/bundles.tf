# ---------------------------------------------------------------------------
# The bundle catalogue.
#
# A bundle is a named, parameterised grant. It exists so that the common cases
# are self-service without anyone hand-writing IAM: a team names what it wants
# and which resource it wants it on, and the actions come from here. That keeps
# the action lists in one reviewed place -- when a bundle turns out to be
# missing a permission, it is fixed once for every repository using it rather
# than copied wrong into the next file.
#
# Every bundle enumerates its resources. None of them accepts a wildcard, and
# none of them builds a resource ARN by prefix match, for the same reason
# service-delivery-foundation does not: an application called
# "checkout-platform-two" must not fall inside "checkout-platform"'s grant.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # ECR repository names follow <application>-<service>. The application
  # defaults to the role key, which is the common case: one role per
  # application, named after it.
  role_application = {
    for role_key, role in var.roles :
    role_key => coalesce(role.application, role_key)
  }

  bundle_statements = {
    for role_key, role in var.roles :
    role_key => flatten([
      for idx, grant in role.grants :

      grant.bundle == "ecr-push" ? [
        {
          # ECR's login call authorises against the registry, which has no
          # per-repository ARN. This is the one resources = tolist(["*"]) the
          # catalogue contains, and it grants a token, not access to an image.
          sid       = "EcrAuth${idx}"
          actions   = tolist(["ecr:GetAuthorizationToken"])
          resources = tolist(["*"])
        },
        {
          sid = "EcrPush${idx}"
          # The read actions are as load-bearing as the writes: buildx
          # resolves the existing manifest before it uploads, and cosign reads
          # back the digest it just pushed in order to sign and attest it.
          # Without BatchGetImage the push fails after the build and the scan
          # have both succeeded.
          actions = tolist([
            "ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload",
            "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload",
            "ecr:PutImage", "ecr:UploadLayerPart",
            "ecr:BatchGetImage", "ecr:DescribeImages",
          ])
          # The real ARNs of the repositories this module creates, not
          # strings built to look like them: the repository and the permission
          # to push to it are the same change, so there is nothing to keep in
          # sync and no way to grant push to a repository that does not exist.
          resources = tolist([
            for service in grant.services :
            module.ecr.repository_arns["${local.role_application[role_key]}-${service}"]
          ])
        },
      ] :

      grant.bundle == "s3-readwrite" ? [
        {
          sid     = "S3Bucket${idx}"
          actions = tolist(["s3:ListBucket", "s3:GetBucketLocation"])
          # Bucket-level actions take the bucket ARN, object-level actions take
          # the object ARN. Conflating the two is why an s3:ListBucket grant
          # that "looks right" returns AccessDenied.
          resources = tolist(["arn:aws:s3:::${grant.bucket}"])
        },
        {
          sid       = "S3Objects${idx}"
          actions   = tolist(["s3:GetObject", "s3:PutObject", "s3:DeleteObject"])
          resources = tolist(["arn:aws:s3:::${grant.bucket}/${grant.prefix}*"])
        },
      ] :

      grant.bundle == "sqs-consume" ? [
        {
          sid = "SqsConsume${idx}"
          actions = tolist([
            "sqs:ReceiveMessage", "sqs:DeleteMessage",
            "sqs:GetQueueAttributes", "sqs:GetQueueUrl",
          ])
          resources = tolist(["arn:aws:sqs:${var.aws_region}:${local.account_id}:${grant.queue}"])
        },
      ] :

      grant.bundle == "dynamodb-readwrite" ? [
        {
          sid = "DynamoTable${idx}"
          actions = tolist([
            "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
            "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchGetItem",
            "dynamodb:BatchWriteItem", "dynamodb:DescribeTable",
          ])
          # The table and its indexes. An index is a separate ARN, so a grant
          # that names only the table fails the moment a Query uses one.
          resources = tolist([
            "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/${grant.table}",
            "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/${grant.table}/index/*",
          ])
        },
      ] :

      [] # unreachable: the bundle name is validated in variables.tf
    ])
  }

  # Escape-hatch statements, sourced by the root module from a directory the
  # requesting team does not own. Normalised into the same shape so the policy
  # document below does not care which half a statement came from.
  exception_statements = {
    for role_key, role in var.roles :
    role_key => [
      for idx, statement in role.raw_statements : {
        sid       = statement.sid != "" ? statement.sid : "Exception${idx}"
        actions   = statement.actions
        resources = statement.resources
      }
    ]
  }

  role_statements = {
    for role_key, role in var.roles :
    role_key => concat(local.bundle_statements[role_key], local.exception_statements[role_key])
  }

  # A role may legitimately exist with no permissions yet -- vended first,
  # granted in a later change. An empty policy document is not valid IAM, so
  # those get a role and no attached policy rather than a failed apply.
  roles_with_statements = {
    for role_key, statements in local.role_statements :
    role_key => statements if length(statements) > 0
  }
}
