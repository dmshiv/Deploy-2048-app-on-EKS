# Deploy Kubernetes manifests for 2048 game - wait for each step to complete
resource "null_resource" "deploy_2048_game" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "Configuring kubectl..."
      aws eks update-kubeconfig --region ${local.aws_region} --name ${local.cluster_name}
      
      echo "Creating namespace..."
      kubectl apply -f ${path.module}/../k8-deploy-yaml-files/namespace.yaml
      
      echo "Deploying 2048 game..."
      kubectl apply -f ${path.module}/../k8-deploy-yaml-files/deployment.yaml
      
      echo "Creating service..."
      kubectl apply -f ${path.module}/../k8-deploy-yaml-files/service.yaml
      
      echo "Waiting for deployment to be ready (no time limit)..."
      until [ $(kubectl get deployment deployment-2048 -n game-2048 -o jsonpath='{.status.readyReplicas}' 2>/dev/null) -eq 3 ]; do
        echo "  Still waiting for all 3 pods to be ready..."
        sleep 10
      done
      echo "✓ Deployment is ready!"
      
      echo "Verifying all pods are Running and Ready (no time limit)..."
      until [ $(kubectl get pods -n game-2048 -l app=game-2048 -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o "True" | wc -l) -eq 3 ]; do
        echo "  Still waiting for all pods to be Ready..."
        sleep 10
      done
      echo "✓ All game pods are Running and Ready!"
      
      echo "Creating ingress (this will trigger ALB creation)..."
      kubectl apply -f ${path.module}/../k8-deploy-yaml-files/ingress.yaml
      
      echo ""
      echo "============================================"
      echo "✅ Deployment successful!"
      echo "============================================"
      echo ""
      echo "⏳ The Application Load Balancer is being created..."
      echo "   This takes 2-3 minutes. You can check status with:"
      echo ""
      echo "   kubectl get ingress -n game-2048 -w"
      echo ""
    EOT
  }

  depends_on = [
    data.terraform_remote_state.alb_controller
  ]
}
