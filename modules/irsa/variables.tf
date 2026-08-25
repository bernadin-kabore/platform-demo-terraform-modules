variable "role_name" {
  description = "IAM role name"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (module.eks.oidc_provider_arn)"
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC provider URL without scheme (module.eks.oidc_provider_url)"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name that will assume this role"
  type        = string
}

variable "policy_arns" {
  description = "Managed IAM policy ARNs to attach"
  type        = list(string)
  default     = []
}

variable "inline_policy_json" {
  description = "Optional inline policy JSON document"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the role"
  type        = map(string)
  default     = {}
}
