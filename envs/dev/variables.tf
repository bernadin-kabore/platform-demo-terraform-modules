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

variable "applications" {
  description = <<-EOT
    Every application the platform delivers, keyed by application name.

    An application is one source repository holding N services. This produces
    one ECR repository per service (<application>-<service>) and one CI role
    per application, federated from that application's source repository.

    Add an entry here when the Backstage scaffolder creates an application —
    until Terraform has run there is no repository to push images to and no
    role for its pipeline to assume.

      applications = {
        checkout-platform = {
          github_owner = "bernadin-kabore"
          services     = ["frontend", "auth", "payments", "worker"]
        }
      }

    This replaced the earlier `services` map and the `ecr_repository_names`
    list, both of which assumed one repository per service and keyed a CI role
    by a repository name that no longer exists.
  EOT
  type = map(object({
    github_owner = string
    services     = list(string)
    source_repo  = optional(string)
  }))
  default = {}
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
