# platform-demo-terraform-modules

Reusable Terraform modules that provision the AWS infrastructure underneath
the platform, plus two composed root modules: `envs/dev` (the AWS side) and
`envs/github-repos` (branch protection across the GitHub org — a different
provider and blast radius, so it gets its own state). This repo owns
**cloud infrastructure and repo governance** — Kubernetes add-ons (Istio,
ArgoCD, Kyverno, etc.) are installed via GitOps from the
[`platform-demo-gitops`](../platform-demo-gitops) repo, not from here.

## Modules

| Module | Purpose |
|---|---|
| [`state-backend`](modules/state-backend) | Bootstraps the S3 + DynamoDB remote state backend (apply once, locally) |
| [`vpc`](modules/vpc) | VPC, public/private subnets, NAT, EKS/Karpenter discovery tags |
| [`eks`](modules/eks) | EKS control plane, OIDC provider, small system node group, core add-ons |
| [`irsa`](modules/irsa) | Generic IAM-Roles-for-Service-Accounts factory, reused per controller |
| [`karpenter`](modules/karpenter) | Karpenter controller/node IAM + spot interruption queue |
| [`ecr`](modules/ecr) | Immutable, scan-on-push ECR repositories |

## Design principles

- **Least privilege via IRSA everywhere.** No controller runs with node-wide
  IAM permissions or static access keys; each gets its own IRSA role scoped
  to exactly the actions it needs (see `envs/dev/main.tf` and the
  `irsa` module).
- **Terraform owns the trust boundary, GitOps owns the workload.** AWS IAM
  roles, the VPC, the cluster, and the container registry are Terraform's
  job. What runs *inside* the cluster — Helm releases, CRDs, policies — is
  ArgoCD's job. This keeps `terraform apply` fast and infrequent, and lets
  add-on versions bump via a PR to the GitOps repo instead of a Terraform run.
- **Small system node group, Karpenter for the rest.** Only core controllers
  (ArgoCD, CoreDNS, Karpenter itself) run on the Terraform-managed node
  group; Karpenter provisions right-sized, largely spot capacity for
  everything else, which is both cheaper and the actual point of the demo.
- **Cost-conscious defaults.** Single NAT gateway, small on-demand system
  nodes, ECR lifecycle rules that expire stale images. Meant to be applied
  for a demo/recording session and torn down (`terraform destroy`)
  afterwards, not run 24/7.

## Getting started

```bash
# 1. Bootstrap remote state (once, with local state)
cd modules/state-backend
terraform init && terraform apply

# 2. Point envs/dev at that backend
cd ../../envs/dev
cp terraform.tfvars.example terraform.tfvars   # edit values, esp. admin_cidrs
# fill in envs/dev/backend.tf or pass -backend-config
terraform init
terraform plan
terraform apply

# 3. Configure kubectl
$(terraform output -raw configure_kubectl)
```

Then continue in [`platform-demo-gitops`](../platform-demo-gitops) to bootstrap ArgoCD
and every cluster add-on.

Separately, [`envs/github-repos`](envs/github-repos) enforces branch
protection (required status checks, including the 70% coverage gate) on
`main`, `develop`, and `release/*` across the platform repos — see that
module's own README.

## CI

`.github/workflows/terraform-ci.yml` runs on every PR: `terraform fmt`,
`validate`, `tflint`, `checkov`, and `tfsec` on lint (matrixed across both
`envs/dev` and `envs/github-repos`), plus a `terraform plan` per root
module — `envs/dev` against real AWS via OIDC federation, `envs/github-repos`
against the GitHub API via a fine-grained PAT — with each plan's output
posted back to the PR.
