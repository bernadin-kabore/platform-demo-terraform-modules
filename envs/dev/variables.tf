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
  type    = list(string)
  default = ["hello-world"]
}

variable "owner" {
  description = "Tag identifying who owns these resources"
  type        = string
  default     = "platform-team"
}
