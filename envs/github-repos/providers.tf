terraform {
  required_version = ">= 1.7.0"
  required_providers {
    github = {
      source  = "integrations/github"
      version = ">= 6.0"
    }
  }
}

# Reads the token from the GITHUB_TOKEN env var — a fine-grained PAT (or a
# GitHub App installation token) with "Administration: read/write" on the
# repos in var.repositories. Never pass it as a Terraform variable/tfvars
# value; it'd end up in state and in the plan output.
provider "github" {
  owner = var.github_org
}
