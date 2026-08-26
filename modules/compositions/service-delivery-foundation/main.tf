data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
  tags            = var.tags
}

module "ecr" {
  source           = "../../ecr"
  repository_names = keys(var.services)
  tags             = var.tags
}

data "aws_iam_policy_document" "ci_trust" {
  for_each = var.services
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
      values   = ["repo:${each.value.github_owner}/${each.key}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "ci" {
  for_each           = var.services
  name               = "${var.name_prefix}-${each.key}-ci"
  assume_role_policy = data.aws_iam_policy_document.ci_trust[each.key].json
  tags               = var.tags
}

data "aws_iam_policy_document" "ci_ecr" {
  for_each = var.services
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
    resources = [module.ecr.repository_arns[each.key]]
  }
}

resource "aws_iam_role_policy" "ci_ecr" {
  for_each = var.services
  name     = "ecr-push"
  role     = aws_iam_role.ci[each.key].id
  policy   = data.aws_iam_policy_document.ci_ecr[each.key].json
}
