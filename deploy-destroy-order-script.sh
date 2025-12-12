# 🚀 TF-apply-destroy-latest.sh - Summary....*********[1]

# What it does (Simple Terms)
# One script to build OR destroy your entire AWS infrastructure in the correct order, showing a visual pipeline as it runs.

# Key Features


# 🔍 Auto-detects folders	Finds all Terraform folders (01-VPC, 02-EKS, etc.) automatically
# 📊 Correct ordering	Apply: 01→02→03... / Destroy: ...03→02→01 (reverse)
# 🌊 Visual pipeline	Shows progress bar filling left-to-right as stages complete
# ⏱️ Timing info	Shows [init:12s, plan:5s, apply:45s] for each folder
# 🔴 Error display	If something fails, shows the actual error immediately
# 🧹 ALB cleanup	Before destroying ALB folder, deletes AWS load balancers first
# 🔄 Auto-retry	If terraform init fails, tries 3 different methods
# 🔒 No prompts	Never asks for input - runs fully automated

# How to Use
# Pick region (or use saved)
# Pick action: Apply (build) or Destroy (teardown)
# Pick folders: all or specific numbers like 1 3 5
# Confirm → Watch the pipeline fill up!


# ╔═══════════════════════════════════════════════════════════════╗
# ║  TERRAFORM PIPELINE  │  Region: eu-central-1  │  Action: apply
# ╚═══════════════════════════════════════════════════════════════╝

# ✓ 01-VPC-Networking [init:12s, plan:5s, apply:45s]
# ✓ 02-EKS-Cluster [init:10s, plan:3s, apply:520s]
# ► 03-EC2-NodeGroup [init:8s, plan...]
# · 04-EBS-CSI-Driver
# · 05-ALB-Controller
# · 06-Robot-Shop-Helm

# ║████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░║

# Progress: 2/6 stages

# Run one command, pick apply or destroy, and watch your entire multi-folder 
# Terraform infrastructure deploy or teardown 
# automatically in the right order with a nice progress display.


# Why the Script Needs Region **************************[2]
# The region is needed for 2 main purposes:

# 1️⃣ AWS CLI Commands (ALB Cleanup)
# When you run destroy, the script needs to delete AWS Load Balancers and 
# Target Groups before Terraform destroys them. This prevents Terraform 
# from hanging on resources that are still in-use.

# # These commands REQUIRE --region to know WHERE in AWS to look
# aws elbv2 describe-load-balancers --region "$AWS_REGION" ...
# aws elbv2 delete-load-balancer --region "$AWS_REGION" ...
# aws elbv2 delete-target-group --region "$AWS_REGION" ...

# Without the region, AWS CLI doesn't know which AWS region to query.

# 2️⃣ Display in Pipeline Header
# It's shown in the visual pipeline header so you know which region you're 
# working in:

# Summary: The region is critical for the destroy operation where it cleans up 
# ALBs/Target Groups via AWS CLI. Without it, those commands would fail or use 
# a wrong default region, causing the destroy to hang or fail.

# ****************** 

#!/bin/bash
set -euo pipefail

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Background colors for water effect
BG_BLUE='\033[44m'
BG_GREEN='\033[42m'
BG_RED='\033[41m'

# Pipeline tracking arrays
declare -a stage_status=()
declare -a stage_names=()

# Disable ALL Terraform locking and inputs
export TF_CLI_ARGS="-lock=false"
export TF_CLI_ARGS_init="-lock=false"
export TF_CLI_ARGS_plan="-lock=false"
export TF_CLI_ARGS_apply="-lock=false -auto-approve"
export TF_CLI_ARGS_destroy="-lock=false -auto-approve"
export TF_INPUT=false  # Never prompt for input

LAST_PATHS_FILE=".last_tf_paths"
CONFIG_FILE=".tf-script-config"
projects=()
selected_projects=()

# Default AWS Region (will prompt user to confirm/change)
AWS_REGION=""
ACTION=""

# ═══════════════════════════════════════════════════════════════════════════════
# PIPELINE VISUALIZATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Arrays for tracking
declare -a stage_fill=()
declare -a stage_info=()

# Draw the SINGLE pipeline view - this is the only output during execution
function draw_single_pipeline() {
  clear
  local num=${#selected_projects[@]}
  
  echo ""
  echo -e "  ${CYAN}╔═══════════════════════════════════════════════════════════════════════════════════════╗${NC}"
  echo -e "  ${CYAN}║${NC}  ${WHITE}TERRAFORM PIPELINE${NC}  │  Region: ${YELLOW}${AWS_REGION}${NC}  │  Action: ${YELLOW}${ACTION}${NC}  │  $(date '+%H:%M:%S')        ${CYAN}║${NC}"
  echo -e "  ${CYAN}╚═══════════════════════════════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  
  # Draw folder names with execution info
  for i in "${!selected_projects[@]}"; do
    local name=$(basename "${selected_projects[$i]}")
    local status="${stage_status[$i]:-pending}"
    local info="${stage_info[$i]:-}"
    
    if [[ "$status" == "running" ]]; then
      echo -e "  ${YELLOW}► ${name}${NC} ${GRAY}${info}${NC}"
    elif [[ "$status" == "success" ]]; then
      echo -e "  ${GREEN}✓ ${name}${NC} ${GRAY}${info}${NC}"
    elif [[ "$status" == "failed" ]]; then
      echo -e "  ${RED}✗ ${name}${NC} ${GRAY}${info}${NC}"
    else
      echo -e "  ${GRAY}· ${name}${NC}"
    fi
  done
  echo ""
  
  # Draw the single horizontal pipe with water fill (left to right)
  local pipe_width=70
  local completed=0
  for s in "${stage_status[@]}"; do
    [[ "$s" == "success" ]] && ((completed++)) || true
  done
  
  # Calculate fill based on completed stages
  local filled_width=$((pipe_width * completed / num))
  local empty_width=$((pipe_width - filled_width))
  
  # Add partial fill for running stage
  for i in "${!selected_projects[@]}"; do
    if [[ "${stage_status[$i]:-pending}" == "running" ]]; then
      local extra=$((stage_fill[$i] * pipe_width / num / 100))
      filled_width=$((filled_width + extra))
      empty_width=$((pipe_width - filled_width))
      break
    fi
  done
  
  echo -ne "  ${CYAN}║${NC}${BG_BLUE}"
  for ((j=0; j<filled_width; j++)); do echo -ne " "; done
  echo -ne "${NC}${GRAY}"
  for ((j=0; j<empty_width; j++)); do echo -ne "░"; done
  echo -e "${NC}${CYAN}║${NC}"
  
  echo ""
  echo -e "  ${WHITE}Progress:${NC} ${GREEN}$completed${NC}/${num} stages"
  echo ""
}

# Function to load or prompt for configuration
function configure_settings() {
  echo -e "\n${CYAN}⚙️  Configuration Settings${NC}"
  echo -e "${BLUE}──────────────────────────────────────────────────────────────${NC}"
  
  # Check if config file exists
  if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    echo -e "${GREEN}📋 Loaded saved config:${NC}"
    echo -e "   AWS Region: ${YELLOW}${AWS_REGION}${NC}"
    echo -ne "\n${YELLOW}Use these settings? (y/n): ${NC}"
    read -r use_saved
    if [[ "$use_saved" == "y" ]]; then
      return
    fi
  fi
  
  # Prompt for AWS Region
  echo -e "\n${CYAN}Available AWS Regions:${NC}"
  echo -e "  ${YELLOW}us-east-1${NC}      (N. Virginia)     ${YELLOW}eu-west-1${NC}      (Ireland)"
  echo -e "  ${YELLOW}us-east-2${NC}      (Ohio)            ${YELLOW}eu-west-2${NC}      (London)"
  echo -e "  ${YELLOW}us-west-1${NC}      (N. California)   ${YELLOW}eu-central-1${NC}   (Frankfurt)"
  echo -e "  ${YELLOW}us-west-2${NC}      (Oregon)          ${YELLOW}ap-south-1${NC}     (Mumbai)"
  echo -e "  ${YELLOW}ap-southeast-1${NC} (Singapore)       ${YELLOW}ap-northeast-1${NC} (Tokyo)"
  
  echo -ne "\n${YELLOW}➡️  Enter AWS Region [default: us-east-1]: ${NC}"
  read -r input_region
  AWS_REGION="${input_region:-us-east-1}"
  
  # Save config
  echo "AWS_REGION=\"$AWS_REGION\"" > "$CONFIG_FILE"
  echo -e "${GREEN}✅ Configuration saved to ${CONFIG_FILE}${NC}"
}

# 🔍 Auto-detect and sort Terraform projects by folder prefix (01-, 02-, etc.)
function detect_tf_projects() {
  echo -e "\n${CYAN}📦 Scanning for Terraform projects...${NC}"
  projects=()

  # Find all valid Terraform directories
  while IFS= read -r -d '' dir; do
    if ls "$dir"/*.tf &>/dev/null || [[ "$dir" == "." && $(ls *.tf 2>/dev/null | wc -l) -gt 0 ]]; then
      [[ "$dir" == "." ]] && projects+=(".") || projects+=("$dir")
    fi
  done < <(find . -mindepth 1 -maxdepth 3 -type f -name "*.tf" -exec dirname {} \; | sort -u | tr '\n' '\0')

  if [[ ${#projects[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No valid Terraform projects found${NC}"
    exit 1
  fi

  # Auto-sort projects by numeric prefix (01-, 02-, etc.)
  # This works for ANY folder naming like 01-xxx, 02-yyy, step1-, step2-, etc.
  IFS=$'\n' projects=($(printf '%s\n' "${projects[@]}" | sort -t'-' -k1 -V))
  unset IFS

  echo -e "\n${GREEN}📂 Detected Terraform projects (auto-sorted):${NC}"
  for i in "${!projects[@]}"; do
    printf "${BLUE}%3d.${NC} %s\n" "$((i + 1))" "$([[ "${projects[$i]}" == "." ]] && echo "./" || echo "${projects[$i]}")"
  done
}

# Function to sort projects for apply (ascending) or destroy (descending)
function sort_projects_for_action() {
  local action="$1"
  shift
  local input_projects=("$@")
  
  if [[ "$action" == "apply" ]]; then
    # Sort ascending (01 → 02 → 03...)
    printf '%s\n' "${input_projects[@]}" | sort -t'-' -k1 -V
  else
    # Sort descending for destroy (06 → 05 → 04...)
    printf '%s\n' "${input_projects[@]}" | sort -t'-' -k1 -V -r
  fi
}

# 🧹 Pre-cleanup function for ALB Controller
function cleanup_albs() {
  echo -e "\n${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}🧹 PRE-CLEANUP: AWS Load Balancers${NC}"
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  # Find and delete all Load Balancers
  echo -e "${YELLOW}⏳ Searching for Load Balancers...${NC}"
  local alb_count=0
  
  while IFS= read -r alb_arn; do
    if [[ -n "$alb_arn" ]]; then
      alb_count=$((alb_count + 1))
      local alb_name=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$alb_arn" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerName' \
        --output text 2>/dev/null || echo "unknown")
      
      echo -e "${CYAN}  🗑️  Deleting ALB: ${alb_name}${NC}"
      aws elbv2 delete-load-balancer \
        --load-balancer-arn "$alb_arn" \
        --region "$AWS_REGION" 2>/dev/null || echo -e "${YELLOW}     ⚠️  Already deleted or in-progress${NC}"
    fi
  done < <(aws elbv2 describe-load-balancers \
    --region "$AWS_REGION" \
    --query 'LoadBalancers[*].LoadBalancerArn' \
    --output text 2>/dev/null | tr '\t' '\n')
  
  if [[ $alb_count -eq 0 ]]; then
    echo -e "${GREEN}✅ No Load Balancers found${NC}"
  else
    echo -e "${YELLOW}⏳ Waiting 90 seconds for ALB deletion to complete...${NC}"
    for i in {90..1}; do
      printf "\r${CYAN}   Time remaining: %3d seconds${NC}" $i
      sleep 1
    done
    printf "\r${GREEN}✅ ALB deletion wait complete!                    ${NC}\n"
  fi
  
  # Clean up Target Groups
  echo -e "${YELLOW}⏳ Searching for Target Groups...${NC}"
  local tg_count=0
  
  while IFS= read -r tg_arn; do
    if [[ -n "$tg_arn" ]]; then
      tg_count=$((tg_count + 1))
      local tg_name=$(aws elbv2 describe-target-groups \
        --target-group-arns "$tg_arn" \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupName' \
        --output text 2>/dev/null || echo "unknown")
      
      echo -e "${CYAN}  🗑️  Deleting TG: ${tg_name}${NC}"
      aws elbv2 delete-target-group \
        --target-group-arn "$tg_arn" \
        --region "$AWS_REGION" 2>/dev/null || echo -e "${YELLOW}     ⚠️  Already deleted or in-use${NC}"
    fi
  done < <(aws elbv2 describe-target-groups \
    --region "$AWS_REGION" \
    --query 'TargetGroups[*].TargetGroupArn' \
    --output text 2>/dev/null | tr '\t' '\n')
  
  if [[ $tg_count -eq 0 ]]; then
    echo -e "${GREEN}✅ No Target Groups found${NC}"
  else
    echo -e "${YELLOW}⏳ Waiting 30 seconds for cleanup to stabilize...${NC}"
    sleep 30
  fi
  
  echo -e "${GREEN}✅ Pre-cleanup complete!${NC}"
  echo -e "${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# 🚀 Robust execution engine - updates pipeline with times
# Saves error output to show on failure
TF_ERROR_LOG="/tmp/tf_error_$$.log"

function run_terraform() {
  local path="$1"
  local action="$2"
  local idx="$3"
  local init_time="" plan_time="" action_time=""

  pushd "$path" >/dev/null || return 1

  # 1. INIT with retry logic
  stage_info[$idx]="[init...]"
  draw_single_pipeline
  
  local start=$(date +%s)
  if terraform init -input=false -no-color 2>"$TF_ERROR_LOG" >/dev/null; then
    init_time="$(( $(date +%s) - start ))s"
  else
    if terraform init -input=false -no-color -upgrade 2>"$TF_ERROR_LOG" >/dev/null; then
      init_time="$(( $(date +%s) - start ))s"
    else
      rm -rf .terraform .terraform.lock.hcl 2>/dev/null
      if terraform init -input=false -no-color 2>"$TF_ERROR_LOG" >/dev/null; then
        init_time="$(( $(date +%s) - start ))s"
      else
        stage_info[$idx]="[init: FAILED]"
        popd >/dev/null
        return 1
      fi
    fi
  fi
  
  stage_info[$idx]="[init:${init_time}]"
  stage_fill[$idx]=30
  draw_single_pipeline

  if [[ "$action" == "destroy" ]]; then
    # PRE-DESTROY CLEANUP for ALB
    if [[ "$path" == *"ALB"* || "$path" == *"alb"* ]]; then
      popd >/dev/null
      cleanup_albs 2>/dev/null
      pushd "$path" >/dev/null
    fi
    
    # Check resources
    local resources=$(terraform state list 2>/dev/null | wc -l)
    if [[ $resources -eq 0 ]]; then
      stage_info[$idx]="[init:${init_time}, skip:no resources]"
      popd >/dev/null
      return 0
    fi
    
    # DESTROY
    stage_info[$idx]="[init:${init_time}, destroy...]"
    stage_fill[$idx]=50
    draw_single_pipeline
    
    start=$(date +%s)
    if terraform destroy -auto-approve -input=false -no-color 2>"$TF_ERROR_LOG" >/dev/null; then
      action_time="$(( $(date +%s) - start ))s"
      stage_info[$idx]="[init:${init_time}, destroy:${action_time}]"
    else
      stage_info[$idx]="[init:${init_time}, destroy:FAILED]"
      popd >/dev/null
      return 1
    fi
  else
    # PLAN
    stage_info[$idx]="[init:${init_time}, plan...]"
    stage_fill[$idx]=50
    draw_single_pipeline
    
    start=$(date +%s)
    if terraform plan -input=false -no-color -out=tfplan 2>"$TF_ERROR_LOG" >/dev/null; then
      plan_time="$(( $(date +%s) - start ))s"
    else
      stage_info[$idx]="[init:${init_time}, plan:FAILED]"
      popd >/dev/null
      return 1
    fi
    
    # APPLY
    stage_info[$idx]="[init:${init_time}, plan:${plan_time}, apply...]"
    stage_fill[$idx]=70
    draw_single_pipeline
    
    start=$(date +%s)
    if terraform apply -input=false -no-color tfplan 2>"$TF_ERROR_LOG" >/dev/null; then
      action_time="$(( $(date +%s) - start ))s"
      stage_info[$idx]="[init:${init_time}, plan:${plan_time}, apply:${action_time}]"
      rm -f tfplan
    else
      stage_info[$idx]="[init:${init_time}, plan:${plan_time}, apply:FAILED]"
      rm -f tfplan
      popd >/dev/null
      return 1
    fi
  fi

  popd >/dev/null
  return 0
}

# 🌱 Main Execution
clear
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🌱 Terraform Automation Script (Universal)              ║${NC}"
echo -e "${GREEN}║      Auto-detects projects & sorts by folder prefix       ║${NC}"
echo -e "${GREEN}║      by dmshiv - $(date -u '+%Y-%m-%d %H:%M:%S') UTC              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"

# Configure AWS Region first
configure_settings

echo -e "\n${BLUE}──────────────────────────────────────────────────────────────${NC}"
echo -e "1. ${CYAN}Apply${NC}   (create infrastructure)  [Order: 01→02→03→...]"
echo -e "2. ${RED}Destroy${NC} (tear down infrastructure) [Order: ...→03→02→01]"
echo -ne "\n${YELLOW}➡️ Select operation (1-2): ${NC}"
read -r choice

case "$choice" in
  1|2)
    detect_tf_projects
    
    # Determine action
    action="apply"
    [[ "$choice" == "2" ]] && action="destroy"
    ACTION="$action"  # Set global for pipeline display
    
    echo -e "\n${YELLOW}🧮 Enter project numbers (e.g., 1 3 5) or 'all': ${NC}"
    read -r order

    if [[ "$order" == "all" ]]; then
      selected_projects=("${projects[@]}")
    else
      # Split input into array
      read -ra input_array <<< "$order"
      for i in "${input_array[@]}"; do
        if ! [[ "$i" =~ ^[0-9]+$ ]]; then
          echo -e "${RED}❌ Invalid input: '$i' is not a number${NC}"
          exit 1
        fi
        if [[ "$i" -lt 1 ]] || [[ "$i" -gt "${#projects[@]}" ]]; then
          echo -e "${RED}❌ Invalid number: $i (valid range: 1-${#projects[@]})${NC}"
          exit 1
        fi
        selected_projects+=("${projects[$((i-1))]}")
      done
    fi

    # Sort projects in correct order based on action
    echo -e "\n${MAGENTA}🔄 Sorting projects in correct ${action} order...${NC}"
    readarray -t sorted_projects < <(sort_projects_for_action "$action" "${selected_projects[@]}")
    selected_projects=("${sorted_projects[@]}")

    echo -e "\n${CYAN}➡️ Will execute in this order (${action^^}):${NC}"
    for i in "${!selected_projects[@]}"; do
      printf "${YELLOW}%3d.${NC} %s\n" "$((i+1))" "$([[ "${selected_projects[$i]}" == "." ]] && echo "./" || echo "${selected_projects[$i]}")"
    done
    
    # Show dependency warning for destroy
    if [[ "$action" == "destroy" ]]; then
      echo -e "\n${RED}⚠️  WARNING: Destroy will remove ALL resources in reverse order!${NC}"
    fi

    echo -ne "\n${GREEN}✅ Confirm? (y/n): ${NC}"
    read -r confirm
    [[ "$confirm" == "y" ]] || { echo -e "${RED}❌ Aborted.${NC}"; exit 1; }

    # Initialize pipeline status and fill for all stages
    for i in "${!selected_projects[@]}"; do
      stage_status[$i]="pending"
      stage_fill[$i]=0
      stage_info[$i]=""
    done

    # Show initial pipeline view
    draw_single_pipeline
    sleep 1
    
    success_count=0
    total_count=${#selected_projects[@]}
    
    for i in "${!selected_projects[@]}"; do
      path="${selected_projects[$i]}"
      
      # Update status to running
      stage_status[$i]="running"
      stage_fill[$i]=10
      
      # Run terraform with index for updating info
      if run_terraform "$path" "$action" "$i"; then
        success_count=$((success_count + 1))
        stage_status[$i]="success"
        stage_fill[$i]=100
        draw_single_pipeline
        sleep 0.3
      else
        stage_status[$i]="failed"
        draw_single_pipeline
        echo ""
        echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${RED}✗ FAILED at: $(basename "$path")${NC}"
        echo -e "  ${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo -e "  ${YELLOW}ERROR OUTPUT:${NC}"
        if [[ -f "$TF_ERROR_LOG" ]]; then
          cat "$TF_ERROR_LOG" | tail -30 | while read -r line; do
            echo -e "  ${GRAY}│${NC} $line"
          done
          rm -f "$TF_ERROR_LOG"
        fi
        echo ""
        exit 1
      fi
    done

    # Cleanup temp log
    rm -f "$TF_ERROR_LOG"

    # Show final success state
    draw_single_pipeline
    echo ""
    echo -e "  ${BG_GREEN}${WHITE}  ✓ PIPELINE COMPLETED - $success_count/$total_count SUCCESSFUL  ${NC}"
    echo ""
    
    [[ "$action" == "apply" ]] && printf "%s\n" "${selected_projects[@]}" > "$LAST_PATHS_FILE"
    
    # If apply completed, show helpful commands
    if [[ "$action" == "apply" && $success_count -eq $total_count ]]; then
      echo -e "  ${CYAN}Helpful commands:${NC}"
      echo -e "  ${GRAY}kubectl get pods -A${NC}"
      echo -e "  ${GRAY}kubectl get ingress -A${NC}"
    fi
    
    exit 0
    ;;
  *)
    echo -e "${RED}❌ Invalid choice. Exiting.${NC}"
    exit 1
    ;;
esac