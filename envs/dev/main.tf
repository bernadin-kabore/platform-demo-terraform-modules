locals {
  tags = {
    Project     = "platform-engineering-demo"
    Environment = "dev"
    ManagedBy   = "terraform"
    Owner       = var.owner
  }

  # Preserve existing ecr_repository_names callers while the developer-facing
  # services map becomes the preferred capability contract.
  effective_services = length(var.services) > 0 ? var.services : {
    for name in var.ecr_repository_names : name => { github_owner = var.github_owner }
  }
}

module "eks_foundation" {
  source              = "../../modules/compositions/eks-foundation"
  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  vpc_cidr            = var.vpc_cidr
  az_count            = var.az_count
  single_nat_gateway  = true
  public_endpoint     = true
  public_access_cidrs = var.admin_cidrs
  tags                = local.tags
}

module "karpenter_iam" {
  source            = "../../modules/karpenter"
  cluster_name      = module.eks_foundation.cluster_name
  cluster_arn       = module.eks_foundation.cluster_arn
  oidc_provider_arn = module.eks_foundation.oidc_provider_arn
  oidc_provider_url = module.eks_foundation.oidc_provider_url
  tags              = local.tags
}

module "service_delivery" {
  source      = "../../modules/compositions/service-delivery-foundation"
  name_prefix = var.cluster_name
  services    = local.effective_services
  tags        = local.tags
}

# ---------------------------------------------------------------------------
# IRSA roles for the add-ons installed via ArgoCD (platform-demo-gitops repo).
# Terraform owns the AWS-side trust boundary; GitOps owns the Helm release.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "crossplane_aws" {
  statement {
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketPolicy",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:ListBucket",
      "s3:PutBucketEncryption",
      "s3:PutBucketPolicy",
      "s3:PutBucketTagging",
      "s3:PutBucketVersioning",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

module "irsa_crossplane" {
  source               = "../../modules/irsa"
  role_name            = "${var.cluster_name}-crossplane-provider-aws"
  oidc_provider_arn    = module.eks_foundation.oidc_provider_arn
  oidc_provider_url    = module.eks_foundation.oidc_provider_url
  namespace            = "crossplane-system"
  service_account_name = "provider-aws"
  inline_policy_json   = data.aws_iam_policy_document.crossplane_aws.json
  tags                 = local.tags
}

module "irsa_opencost" {
  source               = "../../modules/irsa"
  role_name            = "${var.cluster_name}-opencost"
  oidc_provider_arn    = module.eks_foundation.oidc_provider_arn
  oidc_provider_url    = module.eks_foundation.oidc_provider_url
  namespace            = "opencost"
  service_account_name = "opencost"
  policy_arns          = ["arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess", "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"]
  tags                 = local.tags
}

# Representative policy only. Before a real deploy, sync
# policies/aws-load-balancer-controller.json against the upstream policy at
# kubernetes-sigs/aws-load-balancer-controller (docs/install/iam_policy.json);
# AWS revises the exact action list between controller versions.
module "irsa_aws_lb_controller" {
  source               = "../../modules/irsa"
  role_name            = "${var.cluster_name}-aws-lb-controller"
  oidc_provider_arn    = module.eks_foundation.oidc_provider_arn
  oidc_provider_url    = module.eks_foundation.oidc_provider_url
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  inline_policy_json   = file("${path.module}/policies/aws-load-balancer-controller.json")
  tags                 = local.tags
}

module "irsa_external_dns" {
  source               = "../../modules/irsa"
  role_name            = "${var.cluster_name}-external-dns"
  oidc_provider_arn    = module.eks_foundation.oidc_provider_arn
  oidc_provider_url    = module.eks_foundation.oidc_provider_url
  namespace            = "external-dns"
  service_account_name = "external-dns"
  inline_policy_json   = file("${path.module}/policies/external-dns.json")
  tags                 = local.tags
}

# ---------------------------------------------------------------------------
# AI Platform Agent — access to Claude in Amazon Bedrock, and nothing else.
#
# This is the credential path that made Bedrock the right choice over the
# first-party Anthropic API: there is no key. The agent's pod assumes this role
# through the same IRSA mechanism Crossplane, OpenCost and external-dns already
# use, and the SDK signs each request with the credentials it projects. The
# platform has no secrets-delivery mechanism yet (PLATFORM_ROADMAP.md Part 2
# item 1), so a model API key would have had to be a hand-created Kubernetes
# Secret — exactly the anti-pattern that roadmap item exists to remove.
#
# The GitHub App private key the agent also needs is still that manual Secret,
# because nothing here can deliver it. See
# platform-demo-gitops/apps/ai-platform-agent/deployment.yaml.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "ai_platform_agent_bedrock" {
  statement {
    sid    = "InvokeClaudeModels"
    effect = "Allow"
    actions = [
      # The Messages-API Bedrock endpoint (bedrock-mantle.<region>.api.aws).
      "bedrock-mantle:CreateInference",
    ]
    # Scoped to the specific Claude models this agent is allowed to invoke,
    # rather than to Bedrock as a whole. Both the foundation-model ARN and the
    # inference-profile ARN are listed because the global endpoint routes
    # through a cross-region inference profile; which of the two a given call
    # authorises against depends on the model ID prefix the agent sends.
    resources = concat(
      [for id in var.bedrock_model_ids : "arn:aws:bedrock:${var.aws_region}::foundation-model/${id}"],
      [for id in var.bedrock_model_ids : "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${id}"],
    )
  }
}

module "irsa_ai_platform_agent" {
  source               = "../../modules/irsa"
  role_name            = "${var.cluster_name}-ai-platform-agent"
  oidc_provider_arn    = module.eks_foundation.oidc_provider_arn
  oidc_provider_url    = module.eks_foundation.oidc_provider_url
  namespace            = "ai-platform"
  service_account_name = "ai-platform-agent"
  inline_policy_json   = data.aws_iam_policy_document.ai_platform_agent_bedrock.json
  tags                 = local.tags
}
