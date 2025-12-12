# Variables for Step 2: EKS Cluster
# Most values come from Step 1 via data sources

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.28"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "EKS-2048-Game"
    Environment = "Development"
    ManagedBy   = "Terraform"
    Step        = "2-EKS-Cluster"
  }
}
