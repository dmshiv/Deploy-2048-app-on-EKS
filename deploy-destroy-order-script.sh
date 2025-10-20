#!/bin/bash
set -euo pipefail

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Disable ALL Terraform locking
export TF_CLI_ARGS="-lock=false"
export TF_CLI_ARGS_init="-lock=false"
export TF_CLI_ARGS_plan="-lock=false"
export TF_CLI_ARGS_apply="-lock=false"
export TF_CLI_ARGS_destroy="-lock=false"

LAST_PATHS_FILE=".last_tf_paths"
AWS_REGION="us-east-1"  # Change if needed
projects=()
selected_projects=()

# 🔍 Better project detection that handles edge cases
function detect_tf_projects() {
  echo -e "\n${CYAN}📦 Scanning for Terraform projects...${NC}"
  projects=()

  # Find all valid Terraform directories (including root)
  while IFS= read -r -d '' dir; do
    # Verify it's actually a Terraform project (has .tf files)
    if ls "$dir"/*.tf &>/dev/null || [[ "$dir" == "." && $(ls *.tf 2>/dev/null | wc -l) -gt 0 ]]; then
      [[ "$dir" == "." ]] && projects+=(".") || projects+=("$dir")
    fi
  done < <(find . -mindepth 1 -maxdepth 3 -type f -name "*.tf" -exec dirname {} \; | sort -u | tr '\n' '\0')

  if [[ ${#projects[@]} -eq 0 ]]; then
    echo -e "${RED}❌ No valid Terraform projects found (checked current dir and 3 levels deep)${NC}"
    exit 1
  fi

  echo -e "\n${GREEN}📂 Detected Terraform projects:${NC}"
  for i in "${!projects[@]}"; do
    printf "${BLUE}%3d.${NC} %s\n" "$((i + 1))" "$([[ "${projects[$i]}" == "." ]] && echo "./" || echo "${projects[$i]}")"
  done
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

# 🚀 Robust execution engine with clean one-line output
function run_terraform() {
  local path="$1"
  local action="$2"
  local display_path="$([[ "$path" == "." ]] && echo "./" || echo "$path")"
  local output_line="${#selected_projects[@]}. $display_path"

  pushd "$path" >/dev/null || { echo -e "${RED}❌ Failed to enter directory${NC}"; return 1; }

  # 1. INIT
  echo -ne "${output_line} [init..."
  local start=$(date +%s)
  if terraform init -input=false -no-color &>/dev/null; then
    local duration=$(( $(date +%s) - start ))
    printf " ${GREEN}OK${NC} (%02dm%02ds)]" $((duration/60)) $((duration%60))
  else
    local duration=$(( $(date +%s) - start ))
    printf " ${RED}FAIL${NC} (%02dm%02ds)]" $((duration/60)) $((duration%60))
    popd >/dev/null
    return 1
  fi

  if [[ "$action" == "destroy" ]]; then
    # PRE-DESTROY CLEANUP: If this is ALB Controller, clean ALBs first
    if [[ "$path" == *"ALb"* || "$path" == *"alb"* || "$path" == *"load-balancer"* ]]; then
      popd >/dev/null  # Exit the terraform directory temporarily
      cleanup_albs
      pushd "$path" >/dev/null  # Go back to continue destroy
    fi
    
    # 2a. DESTROY FLOW
    echo -ne " [check..."
    start=$(date +%s)
    local resources=$(terraform state list 2>/dev/null | wc -l)
    duration=$(( $(date +%s) - start ))
    printf " ${YELLOW}%d resources${NC} (%02dm%02ds)]" "$resources" $((duration/60)) $((duration%60))

    if [[ $resources -eq 0 ]]; then
      printf " ${YELLOW}SKIPPED${NC}\n"
      popd >/dev/null
      return 0
    fi

    echo -ne " [destroy..."
    start=$(date +%s)
    if terraform destroy -auto-approve -input=false -no-color &>/dev/null; then
      duration=$(( $(date +%s) - start ))
      printf " ${GREEN}DONE${NC} (%02dm%02ds)]\n" $((duration/60)) $((duration%60))
    else
      duration=$(( $(date +%s) - start ))
      printf " ${RED}FAIL${NC} (%02dm%02ds)]" $((duration/60)) $((duration%60))
      
      # Show error details
      echo -e "\n${RED}━━━━━━━ ERROR DETAILS ━━━━━━━${NC}"
      terraform destroy -auto-approve -input=false -no-color 2>&1 | tail -20
      echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      popd >/dev/null
      return 1
    fi
  else
    # 2b. APPLY FLOW
    echo -ne " [plan..."
    start=$(date +%s)
    if terraform plan -input=false -no-color -out=tfplan &>/dev/null; then
      duration=$(( $(date +%s) - start ))
      printf " ${GREEN}OK${NC} (%02dm%02ds)]" $((duration/60)) $((duration%60))
    else
      duration=$(( $(date +%s) - start ))
      printf " ${RED}FAIL${NC} (%02dm%02ds)]" $((duration/60)) $((duration%60))
      popd >/dev/null
      return 1
    fi

    echo -ne " [apply..."
    start=$(date +%s)
    if terraform apply -input=false -no-color tfplan &>/dev/null; then
      duration=$(( $(date +%s) - start ))
      printf " ${GREEN}DONE${NC} (%02dm%02ds)]\n" $((duration/60)) $((duration%60))
      rm -f tfplan  # Cleanup plan file
    else
      duration=$(( $(date +%s) - start ))
      printf " ${RED}FAIL${NC} (%02dm%02ds)]\n" $((duration/60)) $((duration%60))
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
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   🌱 Terraform Automation Script      ║${NC}"
echo -e "${GREEN}║      by dmshiv - $(date -u '+%Y-%m-%d %H:%M:%S') UTC    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo -e "${BLUE}--------------------------------${NC}"
echo -e "1. ${CYAN}Apply${NC} (create/modify infrastructure)"
echo -e "2. ${RED}Destroy${NC} (tear down infrastructure)"
echo -ne "\n${YELLOW}➡️ Select operation (1-2): ${NC}"
read -r choice

case "$choice" in
  1|2)
    detect_tf_projects
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

    echo -e "\n${CYAN}➡️ Will execute:${NC}"
    for i in "${!selected_projects[@]}"; do
      printf "${YELLOW}%3d.${NC} %s\n" "$((i+1))" "$([[ "${selected_projects[$i]}" == "." ]] && echo "./" || echo "${selected_projects[$i]}")"
    done

    echo -ne "\n${GREEN}✅ Confirm? (y/n): ${NC}"
    read -r confirm
    [[ "$confirm" == "y" ]] || { echo -e "${RED}❌ Aborted.${NC}"; exit 1; }

    # Execute all projects
    echo -e "\n${CYAN}🚀 Starting execution...${NC}\n"
    for i in "${!selected_projects[@]}"; do
      path="${selected_projects[$i]}"
      if ! run_terraform "$path" "$([[ "$choice" == "1" ]] && echo "apply" || echo "destroy")"; then
        echo -e "\n${RED}⛔ Operation failed on $path${NC}"
        exit 1
      fi
    done

    [[ "$choice" == "1" ]] && printf "%s\n" "${selected_projects[@]}" > "$LAST_PATHS_FILE"
    
    echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    ✅ ALL OPERATIONS COMPLETED         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    ;;
  *)
    echo -e "${RED}❌ Invalid choice. Exiting.${NC}"
    exit 1
    ;;
esac