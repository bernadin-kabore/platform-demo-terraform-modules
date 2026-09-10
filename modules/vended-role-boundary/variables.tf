variable "name_prefix" {
  description = "Prefix for the boundary policy name, e.g. \"platform-demo\"."
  type        = string
}

variable "aws_region" {
  description = "The only region vended roles may act in. The region-lock statement refuses the vendable services outside it."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
