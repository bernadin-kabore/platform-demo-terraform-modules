# vpc

Minimal, cost-conscious VPC for an EKS cluster: public + private subnets
across N AZs, one NAT gateway by default, and the tags EKS / the AWS Load
Balancer Controller / Karpenter expect for auto-discovery
(`kubernetes.io/cluster/<name>`, `kubernetes.io/role/elb`,
`kubernetes.io/role/internal-elb`, `karpenter.sh/discovery`).

## Usage

```hcl
module "vpc" {
  source       = "../../modules/vpc"
  name         = "platform-demo"
  cluster_name = "platform-demo"
  vpc_cidr     = "10.20.0.0/16"
  az_count     = 2
  tags         = local.tags
}
```

| Input | Description | Default |
|---|---|---|
| `name` | Resource name prefix | – |
| `cluster_name` | EKS cluster name for discovery tags | – |
| `vpc_cidr` | VPC CIDR block | `10.20.0.0/16` |
| `az_count` | Number of AZs | `2` |
| `single_nat_gateway` | One shared NAT vs. one per AZ | `true` |

| Output | Description |
|---|---|
| `vpc_id` | VPC ID |
| `public_subnet_ids` | Public subnet IDs (ingress, NAT) |
| `private_subnet_ids` | Private subnet IDs (nodes, pods) |
