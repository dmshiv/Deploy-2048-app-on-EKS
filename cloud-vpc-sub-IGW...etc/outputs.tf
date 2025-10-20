# Outputs for STEP 1: VPC & Network Infrastructure
# These outputs will be used by subsequent steps

output "vpc_id" {
  description = "VPC ID where EKS cluster will be deployed"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "cluster_name" {
  description = "Name to be used for the EKS cluster"
  value       = var.cluster_name
}

output "availability_zones" {
  description = "Availability zones used"
  value       = var.availability_zones
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}
