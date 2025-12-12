# Variables for Step 3: Fargate Profiles

variable "game_namespace" {
  description = "Kubernetes namespace for 2048 game"
  type        = string
  default     = "game-2048"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "EKS-2048-Game"
    Environment = "Development"
    ManagedBy   = "Terraform"
    Step        = "3-Fargate-Profiles"
  }
}
