#!/usr/bin/env bash
set -eu

STACK_NAME=${1:-spring-ai-agent-agentinfra}
ARTIFACTS_BUCKET=${2:-spring-ai-agent-artifacts-$(date +%s)}
REGION=${AWS_REGION:-us-east-1}

echo "Deploying CloudFormation stack ${STACK_NAME} in ${REGION} with artifacts bucket ${ARTIFACTS_BUCKET}"

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
read -p "Enter GitHub owner (user or org): " GH_OWNER
read -p "Enter GitHub repo name: " GH_REPO
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

