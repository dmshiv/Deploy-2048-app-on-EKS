# Data sources to read outputs from Step 1 (VPC) and Step 2 (EKS)

data "terraform_remote_state" "vpc" {
  backend = "local"

  config = {
    path = "../terraform-states/step1-vpc.tfstate"
  }
}

data "terraform_remote_state" "eks" {
  backend = "local"

  config = {
    path = "../terraform-states/step2-eks.tfstate"
  }
}

# Import outputs as local values for easier reference
locals {
  cluster_name       = data.terraform_remote_state.eks.outputs.cluster_name
  aws_region         = data.terraform_remote_state.eks.outputs.region
  private_subnet_ids = data.terraform_remote_state.eks.outputs.private_subnet_ids
  cluster_endpoint   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_data    = data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data
}
