# Data sources to read outputs from all previous steps

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

data "terraform_remote_state" "alb_controller" {
  backend = "local"

  config = {
    path = "../terraform-states/step4-alb-controller.tfstate"
  }
}

# Import outputs as local values
locals {
  cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
  aws_region   = data.terraform_remote_state.eks.outputs.region
}
