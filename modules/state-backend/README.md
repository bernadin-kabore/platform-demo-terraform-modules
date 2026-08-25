# state-backend

Bootstraps the S3 bucket + DynamoDB table used as the remote backend for every
other root module in this repo. This module is special: it must be applied
with **local** state (chicken-and-egg problem), once, before anything else.

## Usage

```hcl
module "state_backend" {
  source          = "../../modules/state-backend"
  bucket_name     = "acme-platform-tfstate"
  lock_table_name = "acme-platform-tf-locks"
  tags            = { Project = "platform-engineering-demo" }
}
```

After applying, wire the outputs into the `backend "s3" {}` block of
`envs/dev/backend.tf` and run `terraform init -migrate-state`.
