# Terraform backend configuration
# Uncomment and configure if using remote state
#
# terraform {
#   backend "s3" {
#     bucket         = "terraform-state"
#     key            = "rancher-manager/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }
