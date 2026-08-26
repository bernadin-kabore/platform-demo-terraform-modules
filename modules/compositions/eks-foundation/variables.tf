variable "cluster_name" { type = string }
variable "kubernetes_version" { type = string }
variable "vpc_cidr" { type = string }
variable "az_count" { type = number }
variable "single_nat_gateway" { type = bool }
variable "public_endpoint" { type = bool }
variable "public_access_cidrs" { type = list(string) }
variable "tags" { type = map(string) }
