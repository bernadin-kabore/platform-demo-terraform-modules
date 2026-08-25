variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the control plane"
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "VPC ID the cluster runs in"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for nodes/pods"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (used for the control plane ENIs when public endpoint access is needed)"
  type        = list(string)
}

variable "public_endpoint" {
  description = "Whether the API server is reachable from the public internet"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "system_node_instance_types" {
  description = "Instance types for the small system node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "system_node_desired_size" {
  type    = number
  default = 2
}

variable "system_node_min_size" {
  type    = number
  default = 1
}

variable "system_node_max_size" {
  type    = number
  default = 3
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
