# Terraform backend configuration for nprd-apps
# Uncomment and configure if using remote state
#
# terraform {
#   backend "s3" {
#     bucket         = "terraform-state"
#     key            = "rancher-nprd-apps/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }
