# Backend configuration for Step 5: Game Deployment
# Final step - stores state locally

terraform {
  backend "local" {
    path = "../terraform-states/step5-game-deployment.tfstate"
  }
}
