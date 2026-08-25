# eks

Provisions an EKS cluster with:

- IAM roles for the control plane and a small **system** managed node group
  (default: 2x `t3.medium`, on-demand) that hosts only core controllers —
  ArgoCD, Karpenter, CoreDNS. Everything else (app workloads) is provisioned
  by Karpenter on spot capacity, so this module deliberately keeps the
  Terraform-managed node group tiny.
- An IAM OIDC provider, required for IRSA (see the `irsa` module) and for
  Karpenter's own controller role.
- Core managed add-ons: `vpc-cni`, `kube-proxy`, `coredns`, `aws-ebs-csi-driver`.
- EKS access entries via the new `API` authentication mode (no more
  `aws-auth` ConfigMap wrangling).

## Usage

```hcl
module "eks" {
  source              = "../../modules/eks"
  cluster_name        = "platform-demo"
  kubernetes_version  = "1.30"
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  tags                = local.tags
}
```

## Notes

- Cluster + node IAM roles, OIDC provider, and add-ons are managed here.
  Karpenter's own IAM (controller role + node instance profile + interruption
  queue) lives in the separate `karpenter` module so it can be
  destroyed/recreated independently.
- `system_node_desired_size` is ignored after the first apply
  (`lifecycle.ignore_changes`) so the Cluster Autoscaler/Karpenter — not
  Terraform — owns day-2 scaling of that group if you choose to let it.
