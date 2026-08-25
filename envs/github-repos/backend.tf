# Deliberately separate state from envs/dev: this touches GitHub repo
# settings, not AWS, has a different owner/blast-radius, and changes far
# less often than the cluster does.
terraform {
  backend "s3" {
    # bucket         = "REPLACE-WITH-STATE-BUCKET"
    # key            = "platform-demo/github-repos/terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "REPLACE-WITH-LOCK-TABLE"
    # encrypt        = true
  }
}
