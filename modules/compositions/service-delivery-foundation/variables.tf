variable "name_prefix" { type = string }

variable "tags" { type = map(string) }

variable "platform_services" {
  description = <<-EOT
    The platform's own image-producing repositories — components that were
    never scaffolded, are a single repository producing a single image, and
    whose ECR repository is named after the repository itself because the
    manifests in platform-demo-gitops already reference it that way.

    Example:

      platform_services = {
        platform-demo-ai-agent = { github_owner = "bernadin-kabore" }
      }

    Anything the Backstage scaffolder created is vended by
    platform-demo-role-vending instead, not added here. Nothing in this map
    should be a developer workload.
  EOT
  type        = map(object({ github_owner = string }))
  default     = {}
}
