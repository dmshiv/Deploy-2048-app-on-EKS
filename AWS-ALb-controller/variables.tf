# Variables for Step 4: ALB Controller

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "EKS-2048-Game"
    Environment = "Development"
    ManagedBy   = "Terraform"
    Step        = "4-ALB-Controller"
  }
}
