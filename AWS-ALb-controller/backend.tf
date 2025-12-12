# Backend configuration for Step 4: ALB Controller
# Stores state locally so Step 5 can read it

terraform {
  backend "local" {
    path = "../terraform-states/step4-alb-controller.tfstate"
  }
}
