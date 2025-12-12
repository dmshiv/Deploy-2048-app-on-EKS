# Outputs for Step 4: ALB Controller

output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = aws_iam_role.aws_load_balancer_controller.arn
}

output "alb_controller_installed" {
  description = "Confirmation that ALB Controller is installed"
  value       = "ALB Controller installed and ready"
}

output "cluster_name" {
  description = "EKS cluster name (passed through)"
  value       = local.cluster_name
}

output "region" {
  description = "AWS region (passed through)"
  value       = local.aws_region
}
