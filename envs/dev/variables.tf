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

variable "ecr_repository_names" {
  description = "Deprecated compatibility input; use services instead"
  type        = list(string)
  default     = ["hello-world"]
}

variable "services" {
  description = "One ECR repository and least-privilege GitHub Actions CI role per service"
  type        = map(object({ github_owner = string }))
  default     = {}
}

variable "github_owner" {
  description = "Compatibility owner used for ecr_repository_names entries; services entries should set their own owner"
  type        = string
  default     = "bernadin-kabore"
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
