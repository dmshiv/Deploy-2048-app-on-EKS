# =============================================
# EKS Cluster Setup
# =============================================
# WHAT THIS FILE DOES:
# Creates the EKS cluster (the "house" where your Kubernetes apps live) and sets up
# secure access so both AWS and you can manage it.
#
# WHY IT'S NEEDED:
# EKS is AWS's managed Kubernetes service. This file creates the control plane
# (the brain of Kubernetes) and sets up the OIDC provider so pods can securely
# use AWS permissions (IRSA).
#
# THE PROCESS (5 Steps):
# 1. Create IAM role for EKS - AWS needs permission to manage cluster resources
# 2. Attach policies - give EKS the power to create/manage resources
# 3. Create security group - firewall for the cluster
# 4. Create the actual EKS cluster - the Kubernetes control plane (the main event!)
# 5. Create OIDC provider - enables IRSA (secure AWS access from pods, no keys needed!)
#
# ANALOGY:
# Think of EKS as a hotel building:
# - IAM Role = hotel's business license to operate
# - Security Group = the security system and guards
# - EKS Cluster = the actual hotel building with rooms
# - OIDC Provider = a trusted ID verification system for guests (pods) to access hotel services (AWS)

# 1. IAM ROLE FOR EKS CLUSTER
# What: An AWS identity that the EKS service uses to manage your cluster
# Why: EKS needs permission to create worker nodes, load balancers, etc.
# Does: Says "the eks.amazonaws.com service can use this role to manage resources"

resource "aws_iam_role" "eks_cluster" {
  name = "${local.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# 2. ATTACH AWS MANAGED POLICIES TO EKS ROLE
# What: Connects pre-built AWS permission policies to the EKS role
# Why: These policies give EKS all the permissions it needs to manage the cluster
# Does: Attaches "AmazonEKSClusterPolicy" which allows EKS to create/manage resources

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# 3. SECURITY GROUP FOR EKS CLUSTER
# What: A firewall that controls network traffic to/from the EKS control plane
# Why: Security! We need to control what can talk to the Kubernetes API server
# Does: Allows all outbound traffic (so EKS can talk to AWS services)
#       Inbound traffic is managed by AWS automatically for cluster endpoints

resource "aws_security_group" "eks_cluster" {
  name        = "${local.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${local.cluster_name}-cluster-sg"
    }
  )
}

# 4. CREATE THE ACTUAL EKS CLUSTER (The Main Event!)
# What: The actual Kubernetes control plane managed by AWS
# Why: This is the brain of your Kubernetes cluster - the API server, scheduler, etc.
# Does: 
#   - Creates EKS control plane in version 1.28
#   - Places it in both public and private subnets (high availability)
#   - Enables both public and private API access
#   - Configures security group for cluster communication
#   Think of it as building the "command center" for all your containerized apps!

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(local.public_subnet_ids, local.private_subnet_ids)
    endpoint_private_access = true
    endpoint_public_access  = true
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  # Enable control plane logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]

  tags = var.tags
}

# 5. OIDC PROVIDER (The Secret Sauce for IRSA!)
# What: Creates an OIDC (OpenID Connect) identity provider in AWS
# Why: This is THE KEY to IRSA! It lets AWS trust tokens from your Kubernetes cluster
#      Without this, pods can't securely use AWS IAM roles
# Does: 
#   - Gets the TLS certificate from your EKS cluster's OIDC endpoint
#   - Registers it with AWS IAM as a trusted identity provider
#   - Now Kubernetes service accounts can be linked to AWS IAM roles!
#   Think of it as setting up a secure "handshake" between Kubernetes and AWS

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = var.tags
}
