data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

# Two kinds of image-producing repository, deliberately kept apart.
#
# An APPLICATION is what the Backstage scaffolder creates: one source
# repository holding N services, each publishing its own image. ECR
# repositories are keyed per service (<application>-<service>), because a
# service is what produces an artifact; the CI role is keyed per application,
# because a GitHub repository is what an OIDC identity can be federated for.
# A role per service would not be tighter — every service's build job runs in
# the same repository on the same branch, so all of them present an identical
# subject claim. The real boundary is the application: checkout-platform's
# pipeline can push to checkout-platform's image repositories and no others.
#
# A PLATFORM SERVICE is one of the platform's own components — the AI Platform
# Agent, say — which is a single repository producing a single image and was
# never scaffolded. Its ECR repository is named after the repository itself,
# because that is what the manifests in platform-demo-gitops already reference.
# Modelling it as a one-service application would rename its image for no
# reason other than to make the type uniform.
locals {
  # { "checkout-platform-auth" = { application = "checkout-platform", ... } }
  application_services = merge([
    for app_name, app in var.applications : {
      for service in app.services :
      "${app_name}-${service}" => {
        application = app_name
        service     = service
      }
    }
  ]...)

  # { "checkout-platform" = ["checkout-platform-auth", "checkout-platform-payments"] }
  application_ecr_repositories = {
    for app_name, app in var.applications :
    app_name => [for service in app.services : "${app_name}-${service}"]
  }

  # Everything that needs an ECR repository, whichever kind it is.
  ecr_repository_names = concat(
    keys(local.application_services),
    keys(var.platform_services),
  )

  # Every CI role, keyed identically to how it is consumed: the map key is what
  # the operator looks up in the ci_role_arns output to set AWS_CI_ROLE_ARN.
  ci_roles = merge(
    {
      for app_name, app in var.applications : app_name => {
        github_repo = coalesce(app.source_repo, "${app_name}-source")
        owner       = app.github_owner
        # Every service repository belonging to this application.
        ecr_repositories = local.application_ecr_repositories[app_name]
      }
    },
    {
      for repo_name, svc in var.platform_services : repo_name => {
        github_repo      = repo_name
        owner            = svc.github_owner
        ecr_repositories = [repo_name]
      }
    },
  )
}

module "ecr" {
  source           = "../../ecr"
  repository_names = local.ecr_repository_names
  tags             = var.tags
}

data "aws_iam_policy_document" "ci_trust" {
  for_each = local.ci_roles
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # The SOURCE repository, on main only. Never the GitOps repository — that
      # one builds and publishes nothing, and giving it a push credential would
      # undo the separation the whole model exists for.
      values = ["repo:${each.value.owner}/${each.value.github_repo}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "ci" {
  for_each           = local.ci_roles
  name               = "${var.name_prefix}-${each.key}-ci"
  assume_role_policy = data.aws_iam_policy_document.ci_trust[each.key].json
  tags               = var.tags
}

data "aws_iam_policy_document" "ci_ecr" {
  for_each = local.ci_roles
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload",
      "ecr:PutImage", "ecr:UploadLayerPart",
    ]
    # Exactly this caller's repositories, enumerated. Not a wildcard over the
    # account's registry, and not a prefix match that a later application
    # called "checkout-platform-two" would fall inside.
    resources = [
      for repository in each.value.ecr_repositories :
      module.ecr.repository_arns[repository]
    ]
  }
}

resource "aws_iam_role_policy" "ci_ecr" {
  for_each = local.ci_roles
  name     = "ecr-push"
  role     = aws_iam_role.ci[each.key].id
  policy   = data.aws_iam_policy_document.ci_ecr[each.key].json
}
