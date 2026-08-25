# envs/github-repos

Branch protection as code: `main`, `develop`, and every `release/*` branch
on each repo in `var.repositories` requires the `test`, `sast`, `sca`, and
`coverage / check` status checks to pass — and stay passing against an
up-to-date branch (`strict = true`) — before a PR can merge. This is what
actually enforces the 70% coverage gate defined in
[`code-coverage.yml`](../../../platform-demo-hello-world-template/.github/workflows/code-coverage.yml);
the workflow only produces a pass/fail signal, GitHub won't block anything
on it unless a rule like this says to.

## Why a separate root module

Different blast radius and a different owner (GitHub org admin, not AWS)
than `envs/dev`, and it changes far less often — no reason to couple its
state or its apply cadence to the cluster's.

## Usage

```bash
export GITHUB_TOKEN=ghp_...   # fine-grained PAT: Administration r/w on the target repos
cp terraform.tfvars.example terraform.tfvars   # set github_org
terraform init
terraform apply
```

## Onboarding a scaffolded service repo

Add its name to `repositories` and re-apply. That's a manual step by
design in this demo — the alternative (having this module read
`platform-demo-gitops/services/*/config.json` and re-apply automatically on
every merge there) is a natural next step for a real platform team, but
adds a CI-triggers-Terraform dependency this repo set intentionally keeps
out of scope.
