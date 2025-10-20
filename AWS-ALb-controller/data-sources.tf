# Data sources to read outputs from previous steps

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

data "terraform_remote_state" "fargate" {
  backend = "local"

  config = {
    path = "../terraform-states/step3-fargate.tfstate"
  }
}

# Import outputs as local values
locals {
  cluster_name       = data.terraform_remote_state.eks.outputs.cluster_name
  aws_region         = data.terraform_remote_state.eks.outputs.region
  vpc_id             = data.terraform_remote_state.vpc.outputs.vpc_id
  cluster_endpoint   = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_data    = data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data
  oidc_provider_arn  = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  oidc_provider_url  = data.terraform_remote_state.eks.outputs.oidc_provider_url
}
