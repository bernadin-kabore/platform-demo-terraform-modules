locals {
  tags = {
    Project     = "platform-engineering-demo"
    Environment = "dev"
    ManagedBy   = "terraform"
    Owner       = var.owner
  }
}

module "vpc" {
  source             = "../../modules/vpc"
  name               = var.cluster_name
  cluster_name       = var.cluster_name
  vpc_cidr           = var.vpc_cidr
  az_count           = var.az_count
  single_nat_gateway = true
  tags               = local.tags
}

module "eks" {
  source              = "../../modules/eks"
  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  public_access_cidrs = var.admin_cidrs
  tags                = local.tags
}

module "karpenter_iam" {
  source            = "../../modules/karpenter"
  cluster_name      = module.eks.cluster_name
  cluster_arn       = module.eks.cluster_arn
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  tags              = local.tags
}

module "ecr" {
  source           = "../../modules/ecr"
  repository_names = var.ecr_repository_names
  tags             = local.tags
}

# ---------------------------------------------------------------------------
# IRSA roles for the add-ons installed via ArgoCD (platform-demo-gitops repo).
# Terraform owns the AWS-side trust boundary; GitOps owns the Helm release.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "crossplane_aws" {
  statement {
    effect    = "Allow"
    actions   = ["*"]
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
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "crossplane-system"
  service_account_name = "provider-aws"
  inline_policy_json   = data.aws_iam_policy_document.crossplane_aws.json
  tags                 = local.tags
}

module "irsa_opencost" {
  source               = "../../modules/irsa"
  role_name            = "${var.cluster_name}-opencost"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "opencost"
  service_account_name = "opencost"
  policy_arns          = ["arn:aws:iam::aws:policy/AWSBillingReadOnlyAccess", "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"]
  tags                 = local.tags
}

module "irsa_aws_lb_controller" {
  source               = "../../modules/irsa"
  role_name            = "${var.cluster_name}-aws-lb-controller"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  inline_policy_json   = file("${path.module}/policies/aws-load-balancer-controller.json")
  tags                 = local.tags
}

module "irsa_external_dns" {
  source               = "../../modules/irsa"
  role_name            = "${var.cluster_name}-external-dns"
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider_url
  namespace            = "external-dns"
  service_account_name = "external-dns"
  inline_policy_json   = file("${path.module}/policies/external-dns.json")
  tags                 = local.tags
}
