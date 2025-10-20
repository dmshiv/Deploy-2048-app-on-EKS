# Outputs for Step 3: Fargate Profiles

output "fargate_profile_game_2048" {
  description = "Fargate profile ID for game-2048 namespace"
  value       = aws_eks_fargate_profile.game_2048.id
}

output "fargate_profile_kube_system" {
  description = "Fargate profile ID for kube-system namespace"
  value       = aws_eks_fargate_profile.kube_system.id
}

output "cluster_name" {
  description = "EKS cluster name (passed through)"
  value       = local.cluster_name
}

output "region" {
  description = "AWS region (passed through)"
  value       = local.aws_region
}
