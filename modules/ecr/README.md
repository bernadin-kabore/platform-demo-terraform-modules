# ecr

Creates one immutable, KMS-encrypted ECR repository per application, with
scan-on-push plus continuous enhanced scanning at the registry level and a
lifecycle policy that expires untagged images after 7 days and keeps only
the last 20 tagged images.

Image **signing** (cosign, keyless via OIDC/Fulcio) and **SBOM generation**
(Syft) happen in CI (`platform-demo-hello-world-template/skeleton/.github/workflows/ci.yml`)
before push; **signature/SBOM verification and PSS enforcement** happen at
admission via Kyverno (`platform-demo-gitops/apps/kyverno/policies`). This module
only owns the registry, not the supply-chain policy.

## Usage

```hcl
module "ecr" {
  source            = "../../modules/ecr"
  repository_names  = ["hello-world"]
  tags              = local.tags
}
```
