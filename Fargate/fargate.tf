# =============================================
# AWS Fargate Setup for EKS
# =============================================
# WHAT THIS FILE DOES:
# Sets up Fargate profiles so your pods run serverless (no EC2 instances to manage!).
# Also patches CoreDNS to run on Fargate instead of EC2.
#
# WHY IT'S NEEDED:
# Fargate is AWS's serverless container service. Instead of managing EC2 worker nodes,
# Fargate automatically provisions and scales the compute for your pods.
# It's like having invisible workers that appear when needed!
#
# THE PROCESS (6 Steps):
# 1. Create IAM role for Fargate - pods need permission to run
# 2. Attach policy - give Fargate permissions to pull images, write logs, etc.
# 3. Create Fargate profile for game namespace - where game pods run
# 4. Create Fargate profile for kube-system - where CoreDNS and ALB controller run
# 5. Patch CoreDNS - move it from EC2 to Fargate
# 6. Verify CoreDNS is working - make sure DNS resolution works
#
# ANALOGY:
# Think of Fargate as a hotel with invisible staff:
# - Traditional EC2 = you hire and manage your own staff (worker nodes)
# - Fargate = staff magically appear when guests (pods) arrive, disappear when they leave
# - You only pay for the exact time guests stay!

# 1. IAM ROLE FOR FARGATE PODS
# What: An AWS identity that Fargate uses to run your pods
# Why: Fargate needs permission to pull Docker images and write logs to CloudWatch
# Does: Says "the eks-fargate-pods.amazonaws.com service can use this role"
resource "aws_iam_role" "fargate_pod_execution" {
  name = "${local.cluster_name}-fargate-pod-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks-fargate-pods.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# 2. ATTACH FARGATE POLICY TO THE ROLE
# What: Connects AWS's pre-built Fargate policy to the role
# Why: This policy gives Fargate permission to pull images from ECR and write logs to CloudWatch
# Does: Attaches "AmazonEKSFargatePodExecutionRolePolicy" to the role
resource "aws_iam_role_policy_attachment" "fargate_pod_execution_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
  role       = aws_iam_role.fargate_pod_execution.name
}

# 3. FARGATE PROFILE FOR GAME NAMESPACE
# What: Tells EKS "run all pods in the game-2048 namespace on Fargate"
# Why: So your 2048 game pods run serverless without needing EC2 worker nodes
# Does: 
#   - Watches for pods created in the "game-2048" namespace
#   - Automatically launches them on Fargate in private subnets
#   - Scales them up/down as needed
#   Think: "Any pod in game-2048 namespace gets its own invisible Fargate worker!"
resource "aws_eks_fargate_profile" "game_2048" {
  cluster_name           = local.cluster_name
  fargate_profile_name   = "game-2048-profile"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = local.private_subnet_ids

  # Selector: "Any pod in the game-2048 namespace runs on Fargate"
  selector {
    namespace = var.game_namespace
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.fargate_pod_execution_policy
  ]
}

# 4. FARGATE PROFILE FOR KUBE-SYSTEM NAMESPACE
# What: Tells EKS "run CoreDNS and ALB Controller pods on Fargate"
# Why: These critical system pods need to run somewhere! By default they expect EC2 nodes
# Does: 
#   - Has TWO selectors:
#     1. Pods with label "k8s-app=kube-dns" (CoreDNS pods)
#     2. Pods with label "app.kubernetes.io/name=aws-load-balancer-controller" (ALB controller)
#   - Runs them on Fargate in private subnets
#   Think: "System pods get their own invisible Fargate workers too!"
resource "aws_eks_fargate_profile" "kube_system" {
  cluster_name           = local.cluster_name
  fargate_profile_name   = "kube-system-profile"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = local.private_subnet_ids

  # Selector 1: "Pods with label k8s-app=kube-dns in kube-system run on Fargate"
  # (This matches CoreDNS pods)
  selector {
    namespace = "kube-system"
    labels = {
      "k8s-app" = "kube-dns"
    }
  }

  # Selector 2: "Pods with label app.kubernetes.io/name=aws-load-balancer-controller in kube-system run on Fargate"
  # (This matches ALB Controller pods)
  selector {
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name" = "aws-load-balancer-controller"
    }
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.fargate_pod_execution_policy
  ]
}

# 5. PATCH COREDNS TO RUN ON FARGATE (The Tricky Part!)
# What: Modifies CoreDNS deployment to remove "run on EC2" annotation and force it to Fargate
# Why: By default, CoreDNS expects EC2 nodes. Since we're using only Fargate, we need to change this!
# Does:
#   - Waits until CoreDNS deployment exists (polls, no time limit)
#   - Checks if it has the "ec2" compute type annotation
#   - Removes that annotation if present
#   - Deletes existing CoreDNS pods to force recreation on Fargate
#   - Waits until 2 new CoreDNS pods are Running and Ready on Fargate
#   Think: "Moving the hotel phonebook operator from EC2 floor to Fargate floor"
# IMPORTANT: CoreDNS must work before other pods can resolve DNS (like "sts.amazonaws.com")
resource "null_resource" "patch_coredns" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "Configuring kubectl for EKS cluster..."
      aws eks update-kubeconfig --region ${local.aws_region} --name ${local.cluster_name}
      
      echo "Waiting for CoreDNS deployment to exist (no time limit)..."
      until kubectl get deployment coredns -n kube-system &> /dev/null; do
        echo "  Still waiting for CoreDNS deployment..."
        sleep 10
      done
      echo "✓ CoreDNS deployment found!"
      
      # Check if annotation exists before trying to remove it
      ANNOTATION=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.metadata.annotations.eks\.amazonaws\.com/compute-type}' 2>/dev/null || echo "")
      
      if [ "$ANNOTATION" = "ec2" ]; then
        echo "Patching CoreDNS to remove EC2 compute type annotation..."
        kubectl patch deployment coredns \
          -n kube-system \
          --type json \
          -p='[{"op": "remove", "path": "/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]'
        echo "✓ CoreDNS patched successfully!"
      else
        echo "✓ CoreDNS annotation not set to EC2 or already removed, skipping patch..."
      fi
      
      # Delete existing CoreDNS pods to force recreation on Fargate
      echo "Deleting CoreDNS pods to force recreation on Fargate..."
      kubectl delete pod -n kube-system -l k8s-app=kube-dns --ignore-not-found=true
      
      # Wait indefinitely for CoreDNS pods to be running (no timeout)
      echo "Waiting for CoreDNS pods to be running on Fargate (no time limit)..."
      until [ $(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].status.phase}' | grep -o "Running" | wc -l) -ge 2 ]; do
        echo "  Still waiting for CoreDNS pods to be Running..."
        sleep 10
      done
      
      echo "✓ CoreDNS pods are Running! Waiting for them to be fully Ready..."
      until [ $(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o "True" | wc -l) -ge 2 ]; do
        echo "  Still waiting for CoreDNS pods to be Ready..."
        sleep 10
      done
      
      echo "✓✓✓ CoreDNS is fully operational on Fargate!"
      kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
    EOT
  }

  # 6. DEPENDENCY CHAIN (Why This Must Happen in Order)
  # What: Ensures this patching happens only after the kube-system Fargate profile exists
  # Why: If we try to patch CoreDNS before Fargate profile exists, the pods have nowhere to run!
  # Does: Terraform waits for kube_system Fargate profile to be fully created first
  #   Think: "Can't move the phonebook operator to Fargate floor until that floor is built!"
  depends_on = [
    aws_eks_fargate_profile.kube_system
  ]
}

# ════════════════════════════════════════════════════════════════════════════════
# SUMMARY: What Did We Just Build?
# ════════════════════════════════════════════════════════════════════════════════
# 
# 1. Created Fargate permission role (invisible workers need security badge)
# 2. Attached AWS policy (badge gives access to pull images, write logs, talk to EKS)
# 3. Created game-2048 Fargate profile (game app pods run on invisible workers)
# 4. Created kube-system Fargate profile (CoreDNS + ALB Controller run on invisible workers)
# 5. Patched CoreDNS to actually use Fargate (moved phonebook operator to Fargate floor)
# 6. Set up proper dependencies (everything builds in the right order)
#
# CRITICAL CHAIN OF EVENTS:
# ┌─────────────────────────────────────────────────────────────────────────────┐
# │ 1. Fargate profile created → 2. CoreDNS patched → 3. CoreDNS running        │
# │ 4. DNS works → 5. ALB Controller can resolve AWS APIs → 6. Game deploys     │
# └─────────────────────────────────────────────────────────────────────────────┘
#
# If CoreDNS doesn't work on Fargate, NOTHING ELSE WORKS! (No DNS = no name resolution)
# ════════════════════════════════════════════════════════════════════════════════
