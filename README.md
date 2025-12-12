# Deploy 2048 Game on AWS EKS (Terraform + ALB Ingress)

Deploy the classic **2048 web game** on an **AWS EKS** cluster and expose it publicly using the **AWS Load Balancer Controller** (ALB Ingress).

This repo is organized as a **step-by-step Terraform pipeline**:
1) VPC networking
2) EKS cluster
3) Fargate profile
4) AWS Load Balancer Controller (IRSA + Helm)
5) Kubernetes manifests (Namespace/Deployment/Service/Ingress)

---

## Architecture (high level)

- **Terraform** provisions AWS infra (VPC + EKS + IAM + ALB controller)
- **Kubernetes manifests** deploy the 2048 app
- **Ingress (ALB)** exposes the app to the internet

---

## Prerequisites

- AWS account + IAM permissions to create VPC/EKS/IAM/ALB resources
- Tools installed locally:
  - `terraform`
  - `aws` (AWS CLI)
  - `kubectl`
  - `helm`
- AWS credentials configured:

```bash
aws configure
```

---

## Repo layout

```text
Deploy-2048-app-on-EKS/
  cloud-vpc-sub-IGW...etc/          # Step 1: VPC, subnets, IGW, routing
  EKS/                              # Step 2: EKS cluster + OIDC (IRSA)
  Fargate/                          # Step 3: Fargate profile
  AWS-ALb-controller/               # Step 4: AWS Load Balancer Controller (IAM + Helm)
  k8-deploy-yaml-files/             # Kubernetes YAML (namespace, deployment, service, ingress)
  k8-deploy-yaml-files-exec-by-TF/  # Step 5: Terraform triggers kubectl apply
  deploy-destroy-order-script.sh    # Helper script to apply/destroy in correct order
  Tf-apply-destroy-order-pipeline.txt
  output-SS/                        # Screenshots
```

---

## Quick start (recommended)

### Option A — Use the pipeline helper script

This project includes a helper script that applies/destroys Terraform folders **in the correct order**.

```bash
cd /home/dom/K8-abhishek-veeramalla/EKS-projects/Deploy-2048-app-on-EKS
chmod +x deploy-destroy-order-script.sh
./deploy-destroy-order-script.sh
```

- Choose **region** and **apply** when prompted.
- The script handles ordering and also includes ALB cleanup during destroy.

---

## Manual deployment (step-by-step)

> Use this if you prefer running Terraform per folder.

### 1) Create VPC

```bash
cd cloud-vpc-sub-IGW...etc
terraform init
terraform apply -auto-approve
```

### 2) Create EKS cluster

```bash
cd ../EKS
terraform init
terraform apply -auto-approve
```

### 3) Create Fargate profile

```bash
cd ../Fargate
terraform init
terraform apply -auto-approve
```

### 4) Install AWS Load Balancer Controller

```bash
cd ../AWS-ALb-controller
terraform init
terraform apply -auto-approve
```

### 5) Deploy 2048 manifests (via Terraform local-exec)

This folder applies Kubernetes YAML automatically using `kubectl`.

```bash
cd ../k8-deploy-yaml-files-exec-by-TF
terraform init
terraform apply -auto-approve
```

Behind the scenes, it runs (see `k8s-deploy.tf`):
- `aws eks update-kubeconfig ...`
- `kubectl apply` for:
  - `k8-deploy-yaml-files/namespace.yaml`
  - `k8-deploy-yaml-files/deployment.yaml`
  - `k8-deploy-yaml-files/service.yaml`
  - `k8-deploy-yaml-files/ingress.yaml`

---

## Verify

### Check pods

```bash
kubectl get pods -n game-2048
```

### Check service

```bash
kubectl get svc -n game-2048
```

### Get the ALB URL (Ingress)

```bash
kubectl get ingress -n game-2048
```

Wait until the `ADDRESS` field is populated (can take 2–5 minutes). Then open that URL in your browser.

---

## Cleanup (destroy)

### Option A — Use the helper script

```bash
cd /home/dom/K8-abhishek-veeramalla/EKS-projects/Deploy-2048-app-on-EKS
./deploy-destroy-order-script.sh
```

Choose **destroy**.

### Option B — Manual destroy (reverse order)

```bash
cd k8-deploy-yaml-files-exec-by-TF && terraform destroy -auto-approve
cd ../AWS-ALb-controller && terraform destroy -auto-approve
cd ../Fargate && terraform destroy -auto-approve
cd ../EKS && terraform destroy -auto-approve
cd ../cloud-vpc-sub-IGW...etc && terraform destroy -auto-approve
```

---

## Troubleshooting

### Ingress ALB not created

- Ensure the AWS Load Balancer Controller is installed and running.
- Ensure your Ingress uses:
  - `ingressClassName: alb`
  - ALB annotations (see `k8-deploy-yaml-files/ingress.yaml`)

Check:
```bash
kubectl get pods -n kube-system | grep -i load-balancer
kubectl describe ingress -n game-2048 ingress-2048
```

### No external address on Ingress

Wait a few minutes, then watch:
```bash
kubectl get ingress -n game-2048 -w
```

### Pods not ready

```bash
kubectl describe deployment -n game-2048 deployment-2048
kubectl logs -n game-2048 deploy/deployment-2048
```

---

## Notes

- The 2048 container image used is: `public.ecr.aws/l6m2t8p7/docker-2048:latest` (see `k8-deploy-yaml-files/deployment.yaml`).
- Service type is `NodePort` (see `k8-deploy-yaml-files/service.yaml`). ALB Ingress routes traffic to the Service.

---

## Screenshots

See `output-SS/` for deployment and application screenshots.
