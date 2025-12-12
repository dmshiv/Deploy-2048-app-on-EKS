# Outputs for Step 5: Game Deployment

output "game_deployed" {
  description = "Confirmation that 2048 game is deployed"
  value       = "2048 game successfully deployed!"
}

output "get_ingress_url_command" {
  description = "Command to get the ALB URL"
  value       = "kubectl get ingress -n game-2048 ingress-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "game_access_instructions" {
  description = "Instructions to access the game"
  value       = <<-EOT
    
    ========================================
    🎮 2048 GAME DEPLOYED! 🎮
    ========================================
    
    Wait 2-3 minutes for the ALB to finish provisioning, then get the URL:
    
    kubectl get ingress -n game-2048
    
    Or get just the URL:
    kubectl get ingress -n game-2048 ingress-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
    
    Then open in browser: http://<ALB-URL>
    
    ========================================
    
  EOT
}
