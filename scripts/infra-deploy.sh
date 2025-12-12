#!/usr/bin/env bash
set -eu

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

aws cloudformation deploy \
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

aws cloudformation deploy \
  --template-file infra/agent-iam-oidc.yml \
  --stack-name "${OIDC_STACK_NAME}" \
  --region "${REGION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides GitHubOwner=${GH_OWNER} GitHubRepo=${GH_REPO} AgentArtifactsBucket=${ARTIFACTS_BUCKET} AgentLockTable=${STACK_NAME}-AgentLockTable AgentQueueUrl=${STACK_NAME}-AgentQueue

echo "OIDC stack deploy complete"

echo "CloudFormation stacks deployed. Outputs:"
aws cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[0].Outputs' --region ${REGION}
aws cloudformation describe-stacks --stack-name ${OIDC_STACK_NAME} --query 'Stacks[0].Outputs' --region ${REGION}

