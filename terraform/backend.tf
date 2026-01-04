# Terraform Backend Configuration
# Stores state files in the dedicated state/ folder at project root

terraform {
  backend "local" {
    path = "../state/terraform.tfstate"
  }
}
