variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "platform-demo"
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint (lock this to your IP, not 0.0.0.0/0, once past initial demo setup)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "platform_services" {
  description = <<-EOT
    The platform's own image-producing repositories — one repository, one
    image, never scaffolded. Their ECR repository keeps the repository's own
    name because platform-demo-gitops already references it that way.
  EOT
  type        = map(object({ github_owner = string }))
  default     = {}
}

variable "owner" {
  description = "Tag identifying who owns these resources"
  type        = string
  default     = "platform-team"
}

variable "role_vending_repo" {
  description = <<-EOT
    The repository holding the role vending machine, which this root bootstraps
    a CI role for. Leave null to skip creating it — the permissions boundary is
    still created either way, since the vending machine reads it by data source.

    The vending machine cannot create its own CI role: it is the thing that
    creates roles. Something outside it has to go first, and this is it.

      role_vending_repo = {
        github_owner = "bernadin-kabore"
      }

    state_bucket defaults to platform-demo-tfstate-<account id>, the name
    modules/state-backend suggests. Set it only if the vending repository's
    backend.hcl names a different bucket — the CI role's state permissions are
    scoped to exactly that bucket and key prefix.
  EOT
  type = object({
    github_owner     = string
    name             = optional(string, "platform-demo-role-vending")
    state_bucket     = optional(string)
    state_key_prefix = optional(string, "platform-demo/role-vending/")
    lock_table       = optional(string, "platform-demo-terraform-locks")
  })
  default = null
}

variable "bedrock_model_ids" {
  description = <<-EOT
    Claude model IDs the AI Platform Agent may invoke through Amazon Bedrock.
    Model IDs on the Messages-API Bedrock endpoint carry an "anthropic." prefix
    and no date suffix. Listing them explicitly rather than granting Bedrock
    wholesale keeps the agent's blast radius to "can invoke these models".
  EOT
  type        = list(string)
  default     = ["anthropic.claude-opus-5"]
}
