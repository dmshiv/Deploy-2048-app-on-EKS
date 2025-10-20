# =============================================
# AWS Load Balancer Controller Setup
# =============================================
# WHAT THIS FILE DOES:
# This file installs the "doorman" (AWS Load Balancer Controller) that automatically 
# creates AWS Application Load Balancers when you deploy Ingress resources in Kubernetes.
#
# WHY IT'S NEEDED:
# Without this controller, Kubernetes Ingress resources do nothing in AWS.
# With it, you just create an Ingress and boom - AWS creates a real ALB with a public URL!
#
# THE PROCESS (7 Steps):
# 1. Create permission sheet (IAM Policy) - what the controller is allowed to do
# 2. Create identity badge setup (IAM Role with IRSA) - secure way to use AWS from K8s pods
# 3. Create the IAM Role - the actual AWS identity
# 4. Attach permissions to role - give it power
# 5. Wait for CoreDNS - controller needs DNS to talk to AWS APIs
# 6. Install the doorman - Helm installs controller pods
# 7. Verify doorman is ready - make sure it's operational before deploying apps


### 1. PERMISSION SHEET (IAM Policy) **********************************************

# What: A big list of AWS permissions (280+ lines!)
# Why: The controller needs permission to create/manage ALBs, Target Groups, Security Groups, etc.
# Does: Tells AWS "let this controller create and manage load balancers for me"

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "${local.cluster_name}-aws-load-balancer-controller"
  description = "IAM policy for AWS Load Balancer Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = {
            "ec2:CreateAction" = "CreateSecurityGroup"
          }
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:AddTags"
        ]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*"
        ]
        Condition = {
          StringEquals = {
            "elasticloadbalancing:CreateAction" = [
              "CreateTargetGroup",
              "CreateLoadBalancer"
            ]
          }
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule"
        ]
        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

### 2. IDENTITY BADGE SETUP (IAM Role with IRSA)********************************************

# What: Creates a special "assume role" policy that allows Kubernetes service accounts to use AWS permissions
# Why: This is IRSA (IAM Roles for Service Accounts) - it's the secure way to give Kubernetes pods AWS permissions
# Does: Says "only the aws-load-balancer-controller service account in kube-system namespace can use this role"
#       Uses OIDC to verify the pod's identity securely, no AWS keys needed!


data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    principals {
      identifiers = [local.oidc_provider_arn]
      type        = "Federated"
    }
  }
}

### 3. CREATE THE IAM ROLE ********************************************

# What: The actual AWS role that holds all the permissions
# Why: Kubernetes pods need an AWS identity to make AWS API calls
# Does: Creates a role that the controller pod can "wear" to create load balancers

resource "aws_iam_role" "aws_load_balancer_controller" {
  name               = "${local.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role.json

  tags = var.tags
}

### 4. ATTACH PERMISSIONS TO THE ROLE ********************************************

# What: Connects the permission sheet (policy) to the identity badge (role)
# Why: A role without permissions is useless! This gives the role actual power
# Does: Says "this role can now do all those ALB/Target Group/Security Group actions we listed above"

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
  role       = aws_iam_role.aws_load_balancer_controller.name
}

### 5. WAIT FOR DNS TO WORK (CoreDNS Check) ********************************************

# What: Checks that CoreDNS pods are running and DNS resolution works
# Why: The ALB controller needs to resolve AWS API endpoints like "sts.us-east-1.amazonaws.com"
#      If DNS doesn't work, the controller can't talk to AWS and will fail!
# Does: Polls until CoreDNS is ready, then tests that DNS lookups actually work
#       Only proceeds when DNS is 100% operational (no time limit - waits as long as needed)


resource "null_resource" "wait_for_coredns" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "Verifying CoreDNS is operational (no time limit)..."
      aws eks update-kubeconfig --region ${local.aws_region} --name ${local.cluster_name}
      
      # Wait for at least 2 CoreDNS pods to be Ready
      echo "Waiting for CoreDNS pods to be Ready..."
      until [ $(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o "True" | wc -l) -ge 2 ]; do
        echo "  Still waiting for CoreDNS pods..."
        sleep 10
      done
      echo "✓ CoreDNS pods are Ready!"
      
      # Verify kube-dns service has endpoints (much more reliable test!)
      echo "Verifying kube-dns service has endpoints..."
      until [ $(kubectl get endpoints -n kube-system kube-dns -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w) -ge 2 ]; do
        echo "  Waiting for kube-dns endpoints..."
        sleep 5
      done
      
      echo "✓✓✓ CoreDNS is fully operational!"
      kubectl get endpoints -n kube-system kube-dns
    EOT
  }

  depends_on = [
    data.terraform_remote_state.fargate
  ]
}

### 6. INSTALL THE DOORMAN (AWS Load Balancer Controller) ********************************************

# What: Installs a pod called "AWS Load Balancer Controller" in your cluster using Helm
# Why: This is the magic! This pod watches for Ingress resources and tells AWS to create real ALBs
#      Without this controller, Kubernetes Ingress does nothing in AWS
# Does: 
#   - Runs 2 controller pods in kube-system namespace
#   - Watches for Ingress resources you create
#   - Automatically creates AWS ALBs, Target Groups, and Security Groups
#   - Updates ALBs when you change your Ingress
#   - Deletes ALBs when you delete your Ingress
#   Think of it as a "smart doorman" that opens/closes gates (ALBs) for your apps!

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.6.2"
  
  # Wait settings: No rush! Give Fargate time to schedule pods and pull images
  timeout = 3600  # 1 hour - covers even the slowest scenarios
  wait    = true
  wait_for_jobs = true

  # Configuration: Tell the controller about your cluster
  set {
    name  = "clusterName"
    value = local.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }
  
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  # IRSA Magic: Link the Kubernetes service account to the AWS IAM role
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.aws_load_balancer_controller.arn
  }

  set {
    name  = "region"
    value = local.aws_region
  }

  set {
    name  = "vpcId"
    value = local.vpc_id
  }

  depends_on = [
    aws_iam_role_policy_attachment.aws_load_balancer_controller,
    null_resource.wait_for_coredns  # Ensure CoreDNS is fully working first
  ]
}

### 7. VERIFY THE DOORMAN IS READY (Wait for Controller Pods)**********************************************

# What: Waits until the ALB Controller pods are fully running and ready
# Why: We need to make sure the controller is operational before deploying apps
#      If we deploy Ingress before controller is ready, nothing will happen!
# Does: Polls until at least 2 controller pods are in "Ready" state (no time limit)
#       Only continues when the doorman is awake and ready to open gates!
resource "null_resource" "wait_for_alb_controller" {
  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "Waiting for ALB Controller pods to be fully Ready (no time limit)..."
      aws eks update-kubeconfig --region ${local.aws_region} --name ${local.cluster_name}
      
      # Wait for at least 2 ALB controller pods to be Ready
      until [ $(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o "True" | wc -l) -ge 2 ]; do
        echo "  Still waiting for ALB Controller pods..."
        sleep 10
      done
      
      echo "✓✓✓ ALB Controller is fully operational!"
      kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
    EOT
  }

  depends_on = [
    helm_release.aws_load_balancer_controller
  ]
}
