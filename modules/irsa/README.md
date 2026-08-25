# irsa

Generic "IAM Roles for Service Accounts" module: creates one IAM role
trust-scoped to a specific `namespace/service-account` pair via the
cluster's OIDC provider, and attaches whatever managed/inline policies you
give it. One instantiation per controller that needs AWS access.

## Usage

```hcl
module "irsa_karpenter" {
  source                = "../../modules/irsa"
  role_name             = "platform-demo-karpenter-controller"
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_provider_url     = module.eks.oidc_provider_url
  namespace             = "kube-system"
  service_account_name  = "karpenter"
  policy_arns           = [aws_iam_policy.karpenter_controller.arn]
  tags                  = local.tags
}
```

Reused throughout `envs/dev` for Karpenter, Crossplane's `provider-aws`,
external-dns, OpenCost, and the AWS Load Balancer Controller — every
add-on that would otherwise need long-lived AWS access keys stored in a
Kubernetes Secret.
