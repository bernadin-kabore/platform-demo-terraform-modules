variable "name_prefix" {
  description = "Prefix for every vended role name, e.g. \"platform-demo\"."
  type        = string
}

variable "aws_region" {
  description = "Region the vended roles are allowed to act in. The permissions boundary refuses the regional services outside it."
  type        = string
}

variable "oidc_provider_arn" {
  description = <<-DESC
    ARN of the account's GitHub Actions OIDC provider.

    Passed in rather than created here. An account may hold exactly one provider
    for a given issuer URL, and envs/dev already owns
    token.actions.githubusercontent.com through service-delivery-foundation.
    Creating a second one is not a merge conflict Terraform can report -- it is
    an EntityAlreadyExists at apply time, after the plan looked clean.
  DESC
  type        = string
}

variable "roles" {
  description = <<-DESC
    The roles to vend, keyed by the name an operator looks up in the
    role_arns output. One entry per GitHub repository that needs an AWS
    identity.

    `grants` is the self-service half: bundles from the catalogue below, which
    a team may add to its own file without platform review. `raw_statements` is
    the escape hatch, and the root module sources it from a directory a team
    cannot write to -- see envs/role-vending/README.md.
  DESC

  type = map(object({
    github_owner = string
    github_repo  = string

    # ECR repositories are named <application>-<service>, matching what
    # service-delivery-foundation already creates. Defaults to the role key.
    application = optional(string)

    grants = optional(list(object({
      bundle   = string
      services = optional(list(string), []) # ecr-push
      bucket   = optional(string)           # s3-readwrite
      prefix   = optional(string, "")       # s3-readwrite
      queue    = optional(string)           # sqs-consume
      table    = optional(string)           # dynamodb-readwrite
    })), [])

    raw_statements = optional(list(object({
      sid       = optional(string, "")
      actions   = list(string)
      resources = list(string)
    })), [])
  }))

  validation {
    condition = alltrue([
      for role in var.roles : alltrue([
        for grant in role.grants : contains(
          ["ecr-push", "s3-readwrite", "sqs-consume", "dynamodb-readwrite"],
          grant.bundle,
        )
      ])
    ])
    error_message = "Unknown bundle. The catalogue is ecr-push, s3-readwrite, sqs-consume, dynamodb-readwrite. Anything else belongs in exceptions/ as raw_statements, which the platform team owns."
  }

  validation {
    condition = alltrue([
      for role in var.roles : alltrue([
        for grant in role.grants :
        grant.bundle != "ecr-push" || length(grant.services) > 0
      ])
    ])
    error_message = "An ecr-push grant must name at least one service; a role that can push to nothing is a mistake, not a default."
  }

  validation {
    condition = alltrue([
      for role in var.roles : alltrue([
        for grant in role.grants :
        grant.bundle != "s3-readwrite" || try(length(grant.bucket), 0) > 0
      ])
    ])
    error_message = "An s3-readwrite grant must name a bucket. There is deliberately no wildcard form."
  }

  validation {
    condition = alltrue([
      for role in var.roles : alltrue([
        for statement in role.raw_statements :
        !contains([for action in statement.actions : lower(action)], "iam:*") &&
        length([for action in statement.actions : action if startswith(lower(action), "iam:")]) == 0
      ])
    ])
    error_message = "raw_statements may not grant iam:* actions. The permissions boundary refuses them anyway; failing here says so at plan time instead of at runtime."
  }
}

variable "permissions_boundary_arn" {
  description = <<-DESC
    The ceiling attached to every role this module vends, created by
    modules/vended-role-boundary and owned by envs/dev.

    Passed in rather than created here so that the pipeline running this module
    cannot raise its own ceiling. The IAM policy on that pipeline's role pins
    this exact ARN with an iam:PermissionsBoundary condition, so a role created
    without it is refused by IAM rather than by review.
  DESC
  type        = string
}

variable "tags" {
  description = "Tags applied to every vended role."
  type        = map(string)
  default     = {}
}
