data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# The account's one GitHub Actions OIDC provider.
#
# An AWS account holds exactly one provider per issuer URL. This root creates
# it; the role vending machine reads it with a data source rather than
# declaring its own, because a second declaration is not a conflict Terraform
# reports at plan time -- it is EntityAlreadyExists at apply time, against a
# plan that looked clean.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

# The platform's OWN image-producing repositories, and only those.
#
# Applications -- what the Backstage scaffolder creates -- used to be handled
# here too, through an `applications` map in envs/dev/terraform.tfvars. They
# are not any more: they are vended by platform-demo-role-vending from its own
# state, so onboarding an application no longer proposes a plan against the
# state that owns the VPC and the EKS control plane.
#
# What stays here is the handful of components that were never scaffolded, are
# one repository producing one image, and whose ECR repository is named after
# the repository itself because the manifests in platform-demo-gitops already
# reference it that way. Modelling those as applications would rename their
# images for no reason other than uniformity.
locals {
  ecr_repository_names = keys(var.platform_services)

  ci_roles = {
    for repo_name, svc in var.platform_services : repo_name => {
      github_repo      = repo_name
      owner            = svc.github_owner
      ecr_repositories = [repo_name]
    }
  }
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
      #
      # Two forms, because GitHub issues two. The classic subject names the
      # owner and repository as strings; the immutable subject appends numeric
      # IDs to each -- repo:owner@136675538/name@1355406331:ref:... -- so that
      # a rename cannot silently transfer a role's trust to whoever claims the
      # freed name. Which one a repository emits is a GitHub-side setting
      # (GET /repos/{owner}/{repo}/actions/oidc/customization/sub), not
      # something this configuration controls, and it can change under a
      # working pipeline. Matching only the classic form produced exactly that:
      # "Not authorized to perform sts:AssumeRoleWithWebIdentity" against a
      # trust policy that looked correct in every field.
      #
      # The wildcards cover only the ID suffixes. Owner, repository and ref
      # stay pinned, so this is no weaker than one exact string -- a different
      # repository still cannot match.
      values = [
        "repo:${each.value.owner}/${each.value.github_repo}:ref:refs/heads/main",
        "repo:${each.value.owner}@*/${each.value.github_repo}@*:ref:refs/heads/main",
      ]
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
    # The write path is only half of what a push needs. buildx resolves the
    # existing manifest before it uploads -- and cosign, which signs and then
    # attests the digest it just pushed, reads the manifest back the same way --
    # so BatchGetImage and DescribeImages are as load-bearing here as PutImage.
    # Without BatchGetImage the push itself fails, after the build and the scan
    # have both succeeded:
    #
    #   denied: ... not authorized to perform: ecr:BatchGetImage
    #
    # These are reads of the caller's own repositories, scoped identically to
    # the writes below, so nothing widens: the role still cannot see any other
    # application's images.
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:CompleteLayerUpload",
      "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload",
      "ecr:PutImage", "ecr:UploadLayerPart",
      "ecr:BatchGetImage", "ecr:DescribeImages",
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
