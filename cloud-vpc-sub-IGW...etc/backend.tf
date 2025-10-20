# Backend configuration for Step 1: VPC
# Stores state locally so other steps can read it

terraform {
  backend "local" {
    path = "../terraform-states/step1-vpc.tfstate"
  }
}
