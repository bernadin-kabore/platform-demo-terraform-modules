variable "name_prefix" { type = string }

variable "applications" {
  description = <<-EOT
    The applications this platform delivers, keyed by application name.

    Each has one source repository holding every service it lists, and this
    module creates one ECR repository per service (named
    <application>-<service>) plus one GitHub-OIDC CI role per application,
    trusted only from that application's source repository on main.

    Example:

      applications = {
        checkout-platform = {
          github_owner = "bernadin-kabore"
          services     = ["frontend", "auth", "payments", "worker"]
        }
      }

    source_repo defaults to "<application>-source", which is what the Backstage
    scaffolder creates. Set it only for a repository that was named by hand.
  EOT
  type = map(object({
    github_owner = string
    services     = list(string)
    source_repo  = optional(string)
  }))
}

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

    Use `applications` for anything the Backstage scaffolder created. Nothing
    here should be a developer workload.
  EOT
  type        = map(object({ github_owner = string }))
  default     = {}
}
