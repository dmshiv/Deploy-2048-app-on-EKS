# Backend configuration for Step 2: EKS Cluster
# Stores state locally so other steps can read it

terraform {
  backend "local" {
    path = "../terraform-states/step2-eks.tfstate"
  }
}
