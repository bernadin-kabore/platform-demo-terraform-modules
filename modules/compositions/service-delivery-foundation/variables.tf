variable "name_prefix" { type = string }
variable "services" { type = map(object({ github_owner = string })) }
variable "tags" { type = map(string) }
