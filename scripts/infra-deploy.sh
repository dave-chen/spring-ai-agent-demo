#!/usr/bin/env bash
set -euo pipefail

# Usage: infra-deploy.sh [STACK_NAME] [ARTIFACTS_BUCKET] [REGION] [GITHUB_OWNER] [GITHUB_REPO]
STACK_NAME=${1:-spring-ai-agent-agentinfra}
ARTIFACTS_BUCKET=${2:-spring-ai-agent-artifacts-$(date +%s)}
REGION=${3:-${AWS_REGION:-us-east-1}}
GH_OWNER=${4:-${GITHUB_OWNER:-}}
GH_REPO=${5:-${GITHUB_REPO:-}}

check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Required command '$1' not found. Please install it and retry."
    return 1
  fi
  return 0
}

echo "Preparing to deploy CloudFormation stack ${STACK_NAME} in ${REGION} with artifacts bucket ${ARTIFACTS_BUCKET}"

check_command aws || exit 1
check_command jq || echo "Note: jq not found; install to improve JSON output parsing (apt install -y jq)"

# Ensure AWS CLI has credentials and we can call STS
if ! aws sts get-caller-identity --output text >/dev/null 2>&1; then
  echo "ERROR: aws CLI couldn't retrieve caller identity. Check your credentials, region, and permissions (aws configure list)." >&2
  exit 2
fi

# Optional: run local validation (cfn-lint + AWS validate-template if available)
if command -v cfn-lint >/dev/null 2>&1; then
  echo "Running cfn-lint on CloudFormation templates..."
  ./scripts/infra-validate.sh
else
  echo "Note: cfn-lint not found; to lint templates locally install cfn-lint (pip install --user cfn-lint)."
fi

echo "Deploying CloudFormation stack ${STACK_NAME} in ${REGION}"

# Pre-deploy checks: S3 bucket / SQS queue / IAM role conflicts
echo "Checking for resource name conflicts before deploy..."
# S3 bucket check
if aws s3api head-bucket --bucket "${ARTIFACTS_BUCKET}" >/dev/null 2>&1; then
  echo "ERROR: The S3 bucket ${ARTIFACTS_BUCKET} already exists. Choose a different bucket name (globally unique), or delete the existing bucket if you want CloudFormation to manage it." >&2
  echo "You can check the bucket with: aws s3 ls s3://${ARTIFACTS_BUCKET} --recursive --human-readable || true" >&2
  exit 1
fi
# SQS queue check (fifo name must end with .fifo)
if queue_url=$(aws sqs get-queue-url --queue-name "${AgentQueueName:-agent-queue.fifo}" --region "${REGION}" 2>/dev/null || true); then
  if [[ -n "$queue_url" ]]; then
    echo "ERROR: The SQS queue ${AgentQueueName:-agent-queue.fifo} already exists (${queue_url}). Choose a different name or allow CloudFormation to create a new queue name." >&2
    exit 1
  fi
fi
# IAM role check (if role with the same name exists it will cause a create failure)
ROLE_NAME="agent-runtime-role-${STACK_NAME}"
if aws iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  echo "ERROR: IAM role ${ROLE_NAME} already exists in the account; CloudFormation will not take ownership. Choose a different name, or delete the existing role if appropriate." >&2
  exit 1
fi
DEPLOY_OUTPUT=""
  if ! DEPLOY_OUTPUT=$(aws cloudformation deploy \
  --template-file infra/agent-infra.yml \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides AgentArtifactsBucketName=${ARTIFACTS_BUCKET} 2>&1); then
  echo "ERROR: CloudFormation deploy failed for ${STACK_NAME}" >&2
  echo "--- aws deploy output ---" >&2
  echo "$DEPLOY_OUTPUT" >&2
  # If stack exists, show events to help debug; otherwise advise on typical reasons
  if aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "--- CloudFormation stack events (recent) ---" >&2
    aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" --region "${REGION}" --max-items 50 --output json >&2 || true
    if command -v jq >/dev/null 2>&1; then
      echo "--- First FAILURE event ---" >&2
      aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" --region "${REGION}" --max-items 50 --output json | jq -r '.StackEvents[] | select(.ResourceStatus | contains("FAILED")) | "Resource: \(.LogicalResourceId) (\(.ResourceType)) => \(.ResourceStatus): \(.ResourceStatusReason)"' | head -n 5 >&2 || true
    fi
  else
    echo "Stack ${STACK_NAME} does not exist after deploy; ensure you have CreateStack permissions and the AWS account/region is correct." >&2
  fi
  exit 2
fi
  --template-file infra/agent-infra.yml \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides AgentArtifactsBucketName=${ARTIFACTS_BUCKET}

echo "Stack deploy complete"

echo "Now deploying the GitHub OIDC role for repository access"
OIDC_STACK_NAME=${STACK_NAME}-oidc
echo "OIDC stack name: ${OIDC_STACK_NAME}"

# Accept owner/repo from CLI args, environment, or interactive prompt
if [[ -z "${GH_OWNER}" ]]; then
  read -p "Enter GitHub owner (user or org): " GH_OWNER
fi
if [[ -z "${GH_REPO}" ]]; then
  read -p "Enter GitHub repo name: " GH_REPO
fi

echo "Deploying GitHub OIDC role stack ${OIDC_STACK_NAME} in ${REGION}"
DEPLOY_OIDC_OUTPUT=""
if ! DEPLOY_OIDC_OUTPUT=$(aws cloudformation deploy \
  --template-file infra/agent-iam-oidc.yml \
  --stack-name "${OIDC_STACK_NAME}" \
  --region "${REGION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides GitHubOwner=${GH_OWNER} GitHubRepo=${GH_REPO} AgentArtifactsBucket=${ARTIFACTS_BUCKET} AgentLockTable=${STACK_NAME}-AgentLockTable AgentQueueUrl=${STACK_NAME}-AgentQueue 2>&1); then
  echo "ERROR: CloudFormation deploy failed for ${OIDC_STACK_NAME}" >&2
  echo "--- aws deploy output ---" >&2
  echo "$DEPLOY_OIDC_OUTPUT" >&2
  if aws cloudformation describe-stacks --stack-name "${OIDC_STACK_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "--- CloudFormation OIDC stack events (recent) ---" >&2
    aws cloudformation describe-stack-events --stack-name "${OIDC_STACK_NAME}" --region "${REGION}" --max-items 20 --output json >&2 || true
  else
    echo "Stack ${OIDC_STACK_NAME} does not exist after deploy. Check permissions and role trust settings." >&2
  fi
  exit 2
fi
  --template-file infra/agent-iam-oidc.yml \
  --stack-name "${OIDC_STACK_NAME}" \
  --region "${REGION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides GitHubOwner=${GH_OWNER} GitHubRepo=${GH_REPO} AgentArtifactsBucket=${ARTIFACTS_BUCKET} AgentLockTable=${STACK_NAME}-AgentLockTable AgentQueueUrl=${STACK_NAME}-AgentQueue

echo "OIDC stack deploy complete"

echo "CloudFormation stacks deployed. Outputs:"
if aws cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} >/dev/null 2>&1; then
  echo "Stack outputs for ${STACK_NAME}:"
  aws cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[0].Outputs' --region ${REGION}
else
  echo "No stack outputs: ${STACK_NAME} doesn't exist in ${REGION}" >&2
fi
if aws cloudformation describe-stacks --stack-name ${OIDC_STACK_NAME} --region ${REGION} >/dev/null 2>&1; then
  echo "Stack outputs for ${OIDC_STACK_NAME}:"
  aws cloudformation describe-stacks --stack-name ${OIDC_STACK_NAME} --query 'Stacks[0].Outputs' --region ${REGION}
else
  echo "No stack outputs: ${OIDC_STACK_NAME} doesn't exist in ${REGION}" >&2
fi

