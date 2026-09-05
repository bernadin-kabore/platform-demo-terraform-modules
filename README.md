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
| [`compositions/eks-foundation`](modules/compositions/eks-foundation) | Composes `vpc` + `eks` into one cluster foundation |
| [`compositions/service-delivery-foundation`](modules/compositions/service-delivery-foundation) | Per-service ECR repo + least-privilege GitHub Actions CI role, keyed off the `services` map |

## Before the first apply

Two things bite on a clean account, both learned the hard way:

- **`kubernetes_version` must be a version EKS still offers.** AWS retires
  old versions, and an apply against a retired one fails outright. Check
  with `aws eks describe-cluster-versions` before setting it; the value in
  `terraform.tfvars` takes precedence over the module default.
- **ECR enhanced scanning needs Amazon Inspector enabled.** `modules/ecr`
  sets `scan_type = "ENHANCED"`, which fails with a misleading `AccessDenied`
  on `PutRegistryScanningConfiguration` if Inspector is off in the account.
  It is not an IAM problem. The module should arguably own this with an
  `aws_inspector2_enabler` resource.

Note that `terraform destroy` does **not** remove dynamically provisioned
PersistentVolumes; EBS volumes created by in-cluster StorageClasses outlive
the cluster and keep billing. Check for unattached volumes after teardown.

## The AI Platform Agent's AWS footprint

One IRSA role, and it grants one action.

`module.irsa_ai_platform_agent` in `envs/dev/main.tf` lets the agent's pod call
`bedrock-mantle:CreateInference` on the Claude model ARNs listed in
`var.bedrock_model_ids`, and nothing else — no S3, no EKS, no IAM. That is the
entire AWS-side privilege of the component that can open pull requests across
every repository in the platform.

This is the reason the agent runs on Claude in Amazon Bedrock rather than the
first-party Anthropic API: **there is no key to deliver.** The pod assumes the
role through the same IRSA mechanism Crossplane, OpenCost and external-dns
already use, and the SDK signs each request with the credentials it projects.
An API key would instead have needed a hand-created Kubernetes Secret, which is
exactly the anti-pattern `PLATFORM_ROADMAP.md` Part 2 item 1 exists to remove.

The agent's image and CI role come from the existing
`compositions/service-delivery-foundation` rather than anything bespoke — it is
an image-producing repository like any other. Add it to the `services` map in
`terraform.tfvars` (that file is gitignored; see `terraform.tfvars.example`):

```hcl
services = {
  hello-world            = { github_owner = "bernadin-kabore" }
  platform-demo-ai-agent = { github_owner = "bernadin-kabore" }
}
```

The map key must match the GitHub repository name — it is what the CI role's
OIDC subject condition is built from.

`envs/github-repos` protects `platform-demo-ai-agent` on the same terms as the
other four repositories. The agent's own GitHub App appears in no
`bypass_actors` list anywhere, which is what makes "human approval" in the
architecture a real gate: it can propose everywhere and merge nowhere,
including in its own repository.

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
# write backend.hcl naming the bucket/table from step 1 (gitignored - it is
# environment-specific), then:
terraform init -backend-config=backend.hcl
terraform plan -out=tfplan
terraform apply tfplan

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
