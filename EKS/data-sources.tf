# Data sources to read outputs from Step 1 (VPC)

data "terraform_remote_state" "vpc" {
  backend = "local"

  config = {
    path = "../terraform-states/step1-vpc.tfstate"
  }
}

# Import VPC outputs as local values for easier reference
locals {
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  public_subnet_ids  = data.terraform_remote_state.vpc.outputs.public_subnet_ids
  private_subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids
  cluster_name       = data.terraform_remote_state.vpc.outputs.cluster_name
  aws_region         = data.terraform_remote_state.vpc.outputs.region
}
