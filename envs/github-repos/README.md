# envs/github-repos

Branch protection as code for the **4 static platform repos**
(`platform-demo-terraform-modules`, `platform-demo-gitops`,
`platform-demo-backstage`, `platform-demo-hello-world-template`): `main`,
`develop`, and every `release/*` branch requires the `test`, `sast`, `sca`,
and `coverage / check` status checks to pass, requires a PR (no direct
push), requires signed commits, and blocks force-pushes and branch
deletion. This is what actually enforces the 70% coverage gate defined in
[`code-coverage.yml`](../../../platform-demo-hello-world-template/.github/workflows/code-coverage.yml)
— the workflow only produces a pass/fail signal; nothing blocks a merge on
it without a rule like this.

## Why this module doesn't cover scaffolded service repos

Because it *can't*, cleanly — and that gap is itself worth understanding,
since it's a direct consequence of one account-type decision.

**On a GitHub Organization**, `github_organization_ruleset` (see
[`organization-ruleset.tf.example`](organization-ruleset.tf.example)) applies
a ruleset to every repository the org owns by targeting
`conditions.repository_name.include = ["~ALL"]` — including repos that
don't exist yet. Apply it once; every service a developer scaffolds
tomorrow is already covered. No scaffolder step, no Terraform run, no
onboarding checklist item.

**`bernadin-kabore/*` are personal-account repos.** GitHub has no
account-wide equivalent for personal accounts — protection can only be
configured per-repository, after that repository exists. So instead, the
Backstage "hello-world-*" templates call a custom scaffolder action,
[`platform:github:branch-protection`](../../../platform-demo-backstage/packages/backend/src/modules/branch-protection),
right after `publish:github` creates the repo — see that action's own
comments for the full GitHub Rulesets API call it makes. It's still fully
automated (a developer never touches GitHub settings), but it's **automated
per-repo at scaffold time**, not inherited for free the way an
Organization's ruleset would be.

**Moving to an Organization later is a straight swap**, not a redesign:
rename `organization-ruleset.tf.example` to `.tf`, delete the
`github_branch_protection` resources in [`main.tf`](main.tf), delete the
`branch-protection` scaffolder module and its step in every
`template.yaml`. Everything else — the coverage workflow, the required
status check names, the deploy-bot bypass identity — stays exactly as-is,
because both approaches ultimately call the same underlying GitHub
Rulesets concepts.

## The deploy bot bypass identity

Every scaffolded service's CI pushes an automated image-tag bump straight
to `main` after a successful deploy (`update-manifests` job in `ci.yml`).
Once direct pushes to `main` are blocked, that push needs to come from an
identity the ruleset explicitly exempts — a long-lived PAT would work but
is a standing credential to leak and rotate, so this uses a dedicated
GitHub App instead:

1. Create a GitHub App named e.g. `platform-deploy-bot` (Settings →
   Developer settings → GitHub Apps → New). Permissions: **Contents:
   Read & write**, **Metadata: Read-only**. No webhook needed.
2. Install it on every repo it needs to push to (the 4 platform repos, and
   each scaffolded service repo).
3. Generate a private key for it; note its numeric **App ID**.
4. Set `PLATFORM_DEPLOY_BOT_APP_ID` and `PLATFORM_DEPLOY_BOT_PRIVATE_KEY` as
   repo (or org) secrets — consumed by `actions/create-github-app-token` in
   every `ci.yml`'s `update-manifests` job to mint a short-lived
   installation token per run.
5. Set `PLATFORM_DEPLOY_BOT_APP_ID` as the `PLATFORM_DEPLOY_BOT_APP_ID` env
   var wherever Backstage's backend runs, mapped to `app-config.yaml`'s
   `platform.deployBotAppId` — that's what the `platform:github:branch-protection`
   action reads to add the App as a `bypass_actors` entry when it creates
   each new repo's ruleset.

The 4 platform repos have no automated bot pushing to them, so
`require_signed_commits = true` here applies to every contributor with no
exceptions — you'll need commit signing (GPG or SSH) configured locally to
push to any of them.

## Usage

```bash
export GITHUB_TOKEN=ghp_...   # fine-grained PAT: Administration r/w on the target repos
cp terraform.tfvars.example terraform.tfvars   # set github_org
terraform init
terraform apply
```
