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
