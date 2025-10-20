# Backend configuration for Step 3: Fargate Profiles
# Stores state locally so other steps can read it

terraform {
  backend "local" {
    path = "../terraform-states/step3-fargate.tfstate"
  }
}
