# Fill in after applying modules/state-backend once (see its README).
# terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    # bucket         = "REPLACE-WITH-STATE-BUCKET"
    # key            = "platform-demo/dev/terraform.tfstate"
    # region         = "us-east-1"
    # dynamodb_table = "REPLACE-WITH-LOCK-TABLE"
    # encrypt        = true
  }
}
