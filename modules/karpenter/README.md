# karpenter

IAM plumbing for Karpenter, split out from the `eks` module so it can be
upgraded independently:

- **Controller role** (IRSA, `kube-system/karpenter`): scoped EC2 fleet/
  launch-template/tag permissions, `iam:PassRole` limited to the node role
  only, and read access to the spot interruption SQS queue.
- **Node role + instance profile**: what EC2 instances Karpenter launches
  actually run as (same managed policies as the Terraform-managed system
  node group, plus SSM for `kubectl debug`-less troubleshooting).
- **Spot interruption handling**: an SQS queue fed by EventBridge rules for
  spot interruption warnings, rebalance recommendations, and instance
  state-change notifications, so Karpenter can gracefully drain nodes AWS is
  about to reclaim instead of losing pods.

The actual `NodePool`/`EC2NodeClass` Kubernetes objects (which instance
families, spot-vs-on-demand split, consolidation policy) are declared in
`platform-demo-gitops/apps/karpenter`, not here — this module only owns the AWS
side of the trust boundary.

## Usage

```hcl
module "karpenter_iam" {
  source             = "../../modules/karpenter"
  cluster_name       = module.eks.cluster_name
  cluster_arn        = module.eks.cluster_arn
  oidc_provider_arn  = module.eks.oidc_provider_arn
  oidc_provider_url  = module.eks.oidc_provider_url
  tags               = local.tags
}
```
