variable "bucket_name" {
  description = "Globally-unique S3 bucket name for Terraform state"
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name used for state locking"
  type        = string
  default     = "terraform-locks"
}

variable "tags" {
  description = "Tags applied to all resources in this module"
  type        = map(string)
  default     = {}
}
