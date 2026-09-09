variable "cluster_name" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "create_spot_service_linked_role" {
  description = <<-EOT
    Whether to create the account-global EC2 Spot service-linked role.

    Karpenter's default NodePool is spot-first and the first spot fleet request
    in an account fails without it. Set to false if the account already has one
    (created by another stack, or by hand), since a second attempt errors with
    EntityAlreadyExists rather than being a no-op.
  EOT
  type        = bool
  default     = true
}
