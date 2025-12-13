#!/usr/bin/env bash
set -euo pipefail

# Usage: infra-deploy.sh [STACK_NAME] [ARTIFACTS_BUCKET] [REGION] [GITHUB_OWNER] [GITHUB_REPO]
STACK_NAME=${1:-spring-ai-agent-agentinfra}
ARTIFACTS_BUCKET=${2:-spring-ai-agent-artifacts-$(date +%s)}
REGION=${3:-${AWS_REGION:-us-east-1}}
GH_OWNER=${4:-${GITHUB_OWNER:-}}
GH_REPO=${5:-${GITHUB_REPO:-}}
AGENT_ROLE_ARN=${6:-${AGENT_ROLE_ARN:-}}
AGENT_OIDC_ROLE_ARN=${11:-${AGENT_OIDC_ROLE_ARN:-}}
AGENT_OIDC_PROVIDER_ARN=${12:-${AGENT_OIDC_PROVIDER_ARN:-}}
AGENT_OIDC_PROVIDER_HARDCODED_ARN=${13:-${AGENT_OIDC_PROVIDER_HARDCODED_ARN:-}}
DRY_RUN=${DRY_RUN:-${14:-false}}
# Default to the provided OIDC provider ARN for convenience if no value was passed
# NOTE: Replace or remove this default for general public use; this value is account-specific.
if [ -z "${AGENT_OIDC_PROVIDER_ARN:-}" ] && [ -z "${AGENT_OIDC_PROVIDER_DOMAIN:-}" ]; then
  AGENT_OIDC_PROVIDER_ARN=${AGENT_OIDC_PROVIDER_ARN:-arn:aws:iam::970030241939:oidc-provider/token.actions.githubusercontent.com}
  echo "Using default AGENT_OIDC_PROVIDER_ARN=${AGENT_OIDC_PROVIDER_ARN} (from script defaults)"
fi
# Optional behavior flags (env or arg7)
# - ALLOW_EXISTING_BUCKET: if true, reuse existing S3 bucket rather than erroring
# - DELETE_ROLLBACK_STACK: if true, delete an existing ROLLBACK_COMPLETE stack before retrying
ALLOW_EXISTING_BUCKET=${7:-${ALLOW_EXISTING_BUCKET:-false}}
DELETE_ROLLBACK_STACK=${8:-${DELETE_ROLLBACK_STACK:-false}}
# Optional: ALLOW_EXISTING_QUEUE to reuse an existing SQS queue
ALLOW_EXISTING_QUEUE=${9:-${ALLOW_EXISTING_QUEUE:-false}}
# Optional: ALLOW_EXISTING_ROLE to reuse an existing IAM role with the same name
ALLOW_EXISTING_ROLE=${10:-${ALLOW_EXISTING_ROLE:-false}}
# Optional: AWS_PROFILE to use (respect AWS_PROFILE env var). Example: AWS_PROFILE=myprofile
AWS_PROFILE=${AWS_PROFILE:-}
# Optional: ASSUME_ROLE_ARN - if set, assume this role via STS and use temporary credentials
ASSUME_ROLE_ARN=${ASSUME_ROLE_ARN:-}

check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Required command '$1' not found. Please install it and retry."
    return 1
  fi
  return 0
}

# Wrapper to use AWS_PROFILE if set (keeps region consistent via --region)
aws_cmd() {
  if [ -n "${AWS_PROFILE:-}" ]; then
    aws --profile "${AWS_PROFILE}" "$@"
  else
    aws "$@"
  fi
}

echo "Preparing to deploy CloudFormation stack ${STACK_NAME} in ${REGION} with artifacts bucket ${ARTIFACTS_BUCKET}"

check_command aws || exit 1
check_command jq || echo "Note: jq not found; install to improve JSON output parsing (apt install -y jq)"

# If ASSUME_ROLE_ARN provided, assume the role and export temporary credentials
if [ -n "${ASSUME_ROLE_ARN}" ]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required to parse assume-role output; install jq and retry" >&2
    exit 1
  fi
  echo "Assuming role ${ASSUME_ROLE_ARN} to perform deploy actions..."
  ASSUME_OUTPUT=$(aws_cmd sts assume-role --role-arn "${ASSUME_ROLE_ARN}" --role-session-name "infra-deploy-$(date +%s)" --duration-seconds 3600 2>&1) || { echo "ERROR: failed to assume role: $ASSUME_OUTPUT" >&2; exit 1; }
  export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.AccessKeyId')
  export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
  export AWS_SESSION_TOKEN=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.SessionToken')
  echo "Assumed role successfully; using temporary credentials for this session."
fi

# Ensure AWS CLI has credentials and we can call STS
echo "Current AWS caller identity:"
CALLER_ARN=$(aws_cmd sts get-caller-identity --query 'Arn' --output text 2>/dev/null || true)
aws_cmd sts get-caller-identity --output text || true
ACCOUNT_ID=$(aws_cmd sts get-caller-identity --query 'Account' --output text || true)
if [[ "${CALLER_ARN}" == *"AWSReservedSSO"* ]]; then
  echo "Warning: the current credentials appear to be an AWS SSO session (${CALLER_ARN}). To use a different user/profile, run: aws sso login --profile <profile> or set AWS_PROFILE=<profile> or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables." >&2
fi
if ! aws_cmd sts get-caller-identity --output text >/dev/null 2>&1; then
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
# S3 bucket check (optional reuse)
if aws_cmd s3api head-bucket --bucket "${ARTIFACTS_BUCKET}" >/dev/null 2>&1; then
  if [ "${ALLOW_EXISTING_BUCKET}" != "true" ]; then
    echo "ERROR: The S3 bucket ${ARTIFACTS_BUCKET} already exists. Use ALLOW_EXISTING_BUCKET=true to reuse it, or choose a different bucket name (globally unique), or delete the existing bucket if you want CloudFormation to manage it." >&2
    echo "You can check the bucket with: aws s3 ls s3://${ARTIFACTS_BUCKET} --recursive --human-readable || true" >&2
    exit 1
  else
    echo "Reusing existing S3 bucket: ${ARTIFACTS_BUCKET} (ALLOW_EXISTING_BUCKET=true)"
  fi
fi
# SQS queue check (fifo name must end with .fifo)
if queue_url=$(aws_cmd sqs get-queue-url --queue-name "${AgentQueueName:-agent-queue.fifo}" --region "${REGION}" 2>/dev/null || true); then
  if [[ -n "$queue_url" ]]; then
    if [ "${ALLOW_EXISTING_QUEUE}" = "true" ]; then
      echo "Reusing existing SQS queue: ${queue_url} (ALLOW_EXISTING_QUEUE=true)"
      EXISTING_AGENT_QUEUE_URL=${queue_url}
      EXISTING_AGENT_QUEUE_ARN=$(aws_cmd sqs get-queue-attributes --queue-url "${EXISTING_AGENT_QUEUE_URL}" --attribute-names QueueArn --query 'Attributes.QueueArn' --output text --region "${REGION}" 2>/dev/null || true)
      echo "Existing SQS ARN: ${EXISTING_AGENT_QUEUE_ARN}"
    else
      echo "ERROR: The SQS queue ${AgentQueueName:-agent-queue.fifo} already exists (${queue_url}). Choose a different name or set ALLOW_EXISTING_QUEUE=true to reuse it." >&2
      exit 1
    fi
  fi
fi
# IAM role check (if role with the same name exists it will cause a create failure)
ROLE_NAME="agent-runtime-role-${STACK_NAME}"
if aws_cmd iam get-role --role-name "${ROLE_NAME}" >/dev/null 2>&1; then
  EXISTING_ROLE_ARN=$(aws_cmd iam get-role --role-name "${ROLE_NAME}" --query 'Role.Arn' --output text 2>/dev/null || true)
  echo "INFO: IAM role ${ROLE_NAME} already exists in the account (ARN: ${EXISTING_ROLE_ARN})." >&2
  if [ -z "${AGENT_ROLE_ARN}" ]; then
    if [ "${ALLOW_EXISTING_ROLE}" = "true" ]; then
      echo "Using existing IAM role ARN ${EXISTING_ROLE_ARN} (ALLOW_EXISTING_ROLE=true)" >&2
      AGENT_ROLE_ARN=${EXISTING_ROLE_ARN}
    else
      echo "ERROR: IAM role exists and no AGENT_ROLE_ARN provided. Set AGENT_ROLE_ARN or pass ALLOW_EXISTING_ROLE=true to reuse the existing role or delete the role." >&2
      exit 1
    fi
  fi
fi
if [ -n "${AGENT_ROLE_ARN}" ]; then
  echo "Using existing role ARN: ${AGENT_ROLE_ARN}; CloudFormation will not create a new IAM role"
  ROLE_PARAM="AgentRoleArn=${AGENT_ROLE_ARN}"
else
  ROLE_PARAM=""
fi
if [ -n "${EXISTING_AGENT_QUEUE_ARN:-}" ]; then
  QUEUE_PARAM="ExistingAgentQueueArn=${EXISTING_AGENT_QUEUE_ARN} ExistingAgentQueueUrl=${EXISTING_AGENT_QUEUE_URL}"
else
  QUEUE_PARAM=""
fi
DEPLOY_OUTPUT=""
if ! DEPLOY_OUTPUT=$(aws_cmd cloudformation deploy \
  --template-file infra/agent-infra.yml \
  --stack-name "${STACK_NAME}" \
  --region "${REGION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides AgentArtifactsBucketName=${ARTIFACTS_BUCKET} ${ROLE_PARAM} ${QUEUE_PARAM} 2>&1); then
  echo "ERROR: CloudFormation deploy failed for ${STACK_NAME}" >&2
  echo "--- aws deploy output ---" >&2
  echo "$DEPLOY_OUTPUT" >&2
  # If stack exists, show events to help debug; otherwise advise on typical reasons
  STACK_STATUS=""
  if aws_cmd cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "--- CloudFormation stack events (recent) ---" >&2
    aws_cmd cloudformation describe-stack-events --stack-name "${STACK_NAME}" --region "${REGION}" --max-items 50 --output json >&2 || true
    if command -v jq >/dev/null 2>&1; then
      echo "--- First FAILURE event ---" >&2
      aws cloudformation describe-stack-events --stack-name "${STACK_NAME}" --region "${REGION}" --max-items 50 --output json | jq -r '.StackEvents[] | select(.ResourceStatus | contains("FAILED")) | "Resource: \(.LogicalResourceId) (\(.ResourceType)) => \(.ResourceStatus): \(.ResourceStatusReason)"' | head -n 5 >&2 || true
    fi
  else
    echo "Stack ${STACK_NAME} does not exist after deploy; ensure you have CreateStack permissions and the AWS account/region is correct." >&2
  fi
  exit 2
fi
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" --query 'Stacks[0].StackStatus' --output text || true)
if [ "$STACK_STATUS" = "ROLLBACK_COMPLETE" ]; then
  echo "Detected existing stack ${STACK_NAME} in ROLLBACK_COMPLETE state"
  if [ "${DELETE_ROLLBACK_STACK}" = "true" ]; then
    echo "Deleting stack ${STACK_NAME} (DELETE_ROLLBACK_STACK=true) and retrying..."
    aws_cmd cloudformation delete-stack --stack-name "${STACK_NAME}" --region "${REGION}" || true
    echo "Waiting for stack deletion to complete..."
    aws_cmd cloudformation wait stack-delete-complete --stack-name "${STACK_NAME}" --region "${REGION}" || true
    echo "Old stack deleted. Continuing with new deploy..."
  else
    echo "Creating a new stack name by appending timestamp to avoid ROLLBACK_COMPLETE conflicts."
    NEW_SUFFIX=$(date +%s)
    NEW_STACK_NAME="${STACK_NAME}-${NEW_SUFFIX}"
    echo "New stack name: ${NEW_STACK_NAME}"
    STACK_NAME=${NEW_STACK_NAME}
  fi
fi

echo "Stack deploy complete"

echo "Now deploying the GitHub OIDC role for repository access"
OIDC_STACK_NAME=${STACK_NAME}-oidc
echo "OIDC stack name: ${OIDC_STACK_NAME}"

# Fetch outputs from main stack to pass as parameters into OIDC stack
AGENT_QUEUE_URL=$(aws_cmd cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='AgentQueueUrl'].OutputValue" --output text || true)
AGENT_QUEUE_ARN=$(aws_cmd cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='AgentQueueArn'].OutputValue" --output text || true)
AGENT_LOCK_TABLE=$(aws_cmd cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='AgentLockTable'].OutputValue" --output text || true)
AGENT_ARTIFACTS_BUCKET=$(aws_cmd cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} --query "Stacks[0].Outputs[?OutputKey=='AgentArtifactsBucket'].OutputValue" --output text || true)
# Detect an existing GitHub OIDC provider ARN in the account (for token.actions.githubusercontent.com)
EXISTING_OIDC_PROVIDER_ARN=""
for arn in $(aws_cmd iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text 2>/dev/null || true); do
  if [ -n "$arn" ]; then
    # Get provider details
    url=$(aws_cmd iam get-open-id-connect-provider --open-id-connect-provider-arn "$arn" --query 'Url' --output text 2>/dev/null || true)
    if [ "$url" = "https://token.actions.githubusercontent.com" ]; then
      EXISTING_OIDC_PROVIDER_ARN="$arn"
      break
    fi
  fi
done

# If user passed AGENT_OIDC_PROVIDER_ARN or AGENT_OIDC_PROVIDER_DOMAIN via env or CLI, substitute placeholder and normalize
if [ -n "${AGENT_OIDC_PROVIDER_ARN:-}" ]; then
  # Replace CloudFormation placeholder if present
  if [[ "${AGENT_OIDC_PROVIDER_ARN}" == *'${AWS::AccountId}'* ]] || [[ "${AGENT_OIDC_PROVIDER_ARN}" == *"\${AWS::AccountId}"* ]]; then
    if [ -n "${ACCOUNT_ID}" ]; then
      AGENT_OIDC_PROVIDER_ARN=${AGENT_OIDC_PROVIDER_ARN//\\${AWS::AccountId}/${ACCOUNT_ID}}
      echo "Substituted AWS Account ID into AGENT_OIDC_PROVIDER_ARN: ${AGENT_OIDC_PROVIDER_ARN}"
    else
      echo "ERROR: Unable to resolve AWS account id for AGENT_OIDC_PROVIDER_ARN substitution" >&2
      exit 1
    fi
  fi
  # If user supplied a domain (not a full ARN), construct the provider ARN
  if [[ "${AGENT_OIDC_PROVIDER_ARN}" != arn:aws:iam::* ]]; then
    if [[ "${AGENT_OIDC_PROVIDER_ARN}" == *"token.actions.githubusercontent.com"* ]]; then
      if [ -n "${ACCOUNT_ID}" ]; then
        AGENT_OIDC_PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${AGENT_OIDC_PROVIDER_ARN}"
        echo "Normalized AGENT_OIDC_PROVIDER_ARN to ${AGENT_OIDC_PROVIDER_ARN}"
      else
        echo "ERROR: Unable to normalize AGENT_OIDC_PROVIDER_ARN because account ID is unknown" >&2
        exit 1
      fi
    fi
  fi
  EXISTING_OIDC_PROVIDER_ARN=${AGENT_OIDC_PROVIDER_ARN}
  # If user supplied the domain-only, instead pass domain param to CFN (to be constructed by template)
  if [[ "${AGENT_OIDC_PROVIDER_ARN}" == *"token.actions.githubusercontent.com"* && "${AGENT_OIDC_PROVIDER_ARN}" != arn:aws:iam::* ]]; then
    AGENT_OIDC_PROVIDER_DOMAIN=token.actions.githubusercontent.com
    OIDC_PROVIDER_PARAM="AgentOIDCProviderDomain=${AGENT_OIDC_PROVIDER_DOMAIN}"
    EXISTING_OIDC_PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${AGENT_OIDC_PROVIDER_DOMAIN}"
  else
    OIDC_PROVIDER_PARAM="AgentOIDCProviderArn=${AGENT_OIDC_PROVIDER_ARN}"
  fi
fi

if [ -n "${AGENT_OIDC_PROVIDER_DOMAIN:-}" ]; then
  OIDC_PROVIDER_PARAM="AgentOIDCProviderDomain=${AGENT_OIDC_PROVIDER_DOMAIN}"
  # Ensure we set EXISTING_OIDC_PROVIDER_ARN for later use
  EXISTING_OIDC_PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${AGENT_OIDC_PROVIDER_DOMAIN}"
fi
if [ -n "${AGENT_OIDC_PROVIDER_HARDCODED_ARN:-}" ]; then
  # substitute any ${AWS::AccountId} placeholder into the hardcoded ARN
  if [[ "${AGENT_OIDC_PROVIDER_HARDCODED_ARN}" == *'${AWS::AccountId}'* ]] || [[ "${AGENT_OIDC_PROVIDER_HARDCODED_ARN}" == *"\${AWS::AccountId}"* ]]; then
    if [ -n "${ACCOUNT_ID}" ]; then
      AGENT_OIDC_PROVIDER_HARDCODED_ARN=${AGENT_OIDC_PROVIDER_HARDCODED_ARN//\${AWS::AccountId}/${ACCOUNT_ID}}
      echo "Substituted AWS Account ID into AGENT_OIDC_PROVIDER_HARDCODED_ARN: ${AGENT_OIDC_PROVIDER_HARDCODED_ARN}"
    else
      echo "ERROR: Unable to resolve AWS account id to substitute in AGENT_OIDC_PROVIDER_HARDCODED_ARN" >&2
      exit 1
    fi
  fi
  OIDC_PROVIDER_PARAM="AgentOIDCProviderHardcodedArn=${AGENT_OIDC_PROVIDER_HARDCODED_ARN}"
  EXISTING_OIDC_PROVIDER_ARN=${AGENT_OIDC_PROVIDER_HARDCODED_ARN}
fi
if [ -n "$EXISTING_OIDC_PROVIDER_ARN" ]; then
  echo "Found existing OIDC provider ARN: ${EXISTING_OIDC_PROVIDER_ARN}"
fi

# Substitute a literal ${AWS::AccountId} placeholder in commonly provided env vars
substitute_account_placeholder() {
  local name="$1"
  eval local_value="\"\${${name}:-}\""
  if [[ -n "${local_value}" && ( "${local_value}" == *'${AWS::AccountId}'* || "${local_value}" == *"\${AWS::AccountId}"* ) ]]; then
    if [[ -n "${ACCOUNT_ID}" ]]; then
      local_value=${local_value//\${AWS::AccountId}/${ACCOUNT_ID}}
      eval ${name}="\"${local_value}\""
      echo "Substituted \${AWS::AccountId} into ${name}: ${local_value}"
    else
      echo "ERROR: Unable to resolve AWS account id for ${name} substitution" >&2
      exit 1
    fi
  fi
}

# Sanitize values that may be passed as params
substitute_account_placeholder AGENT_OIDC_PROVIDER_ARN
substitute_account_placeholder AGENT_OIDC_PROVIDER_HARDCODED_ARN
substitute_account_placeholder AGENT_OIDC_PROVIDER_DOMAIN
substitute_account_placeholder AGENT_ROLE_ARN
substitute_account_placeholder AGENT_OIDC_ROLE_ARN

# Accept owner/repo from CLI args, environment, or interactive prompt
if [[ -z "${GH_OWNER}" ]]; then
  read -p "Enter GitHub owner (user or org): " GH_OWNER
fi
if [[ -z "${GH_REPO}" ]]; then
  read -p "Enter GitHub repo name: " GH_REPO
fi

# Detect an existing GitHub OIDC role named gh-actions-agent-role-${GH_REPO}
OIDC_ROLE_NAME="gh-actions-agent-role-${GH_REPO}"
if aws_cmd iam get-role --role-name "${OIDC_ROLE_NAME}" >/dev/null 2>&1; then
  EXISTING_OIDC_ROLE_ARN=$(aws_cmd iam get-role --role-name "${OIDC_ROLE_NAME}" --query 'Role.Arn' --output text 2>/dev/null || true)
  echo "INFO: Found existing OIDC role ${OIDC_ROLE_NAME} (ARN: ${EXISTING_OIDC_ROLE_ARN})"
  if [ -n "${AGENT_OIDC_ROLE_ARN}" ]; then
    echo "Using provided OIDC role ARN: ${AGENT_OIDC_ROLE_ARN}; OIDC stack will not create a new IAM role"
    # Extract the role name from the ARN to allow attaching policies
    AGENT_OIDC_ROLE_NAME=$(echo "${AGENT_OIDC_ROLE_ARN}" | awk -F'/' '{print $NF}')
    OIDC_ROLE_PARAM="AgentOIDCRoleArn=${AGENT_OIDC_ROLE_ARN} AgentOIDCRoleName=${AGENT_OIDC_ROLE_NAME}"
    # Verify the provided OIDC role ARN exists and is valid
    if ! aws_cmd iam get-role --role-name "${AGENT_OIDC_ROLE_NAME}" >/dev/null 2>&1; then
      echo "ERROR: Provided AGENT_OIDC_ROLE_ARN points to role ${AGENT_OIDC_ROLE_NAME}, but the role cannot be found. Verify the ARN and role exist in the account (or omit and let CloudFormation create the role)." >&2
      exit 1
    fi
    echo "Ensure the existing role's trust policy includes token.actions.githubusercontent.com as a federated principal to allow GitHub Actions to assume the role via OIDC."
  else
    if [ "${ALLOW_EXISTING_ROLE}" = "true" ]; then
      echo "Reusing existing OIDC role ${EXISTING_OIDC_ROLE_ARN} (ALLOW_EXISTING_ROLE=true)"
      AGENT_OIDC_ROLE_ARN=${EXISTING_OIDC_ROLE_ARN}
      AGENT_OIDC_ROLE_NAME=$(echo "${AGENT_OIDC_ROLE_ARN}" | awk -F'/' '{print $NF}')
      OIDC_ROLE_PARAM="AgentOIDCRoleArn=${AGENT_OIDC_ROLE_ARN} AgentOIDCRoleName=${AGENT_OIDC_ROLE_NAME}"
    else
      echo "Note: OIDC role ${OIDC_ROLE_NAME} exists but ALLOW_EXISTING_ROLE is not set; deploy will attempt to create or error depending on permissions."
    fi
  fi
fi

echo "Deploying GitHub OIDC role stack ${OIDC_STACK_NAME} in ${REGION}"
DEPLOY_OIDC_OUTPUT=""
echo "CloudFormation parameters for OIDC stack: GitHubOwner=${GH_OWNER} GitHubRepo=${GH_REPO} AgentArtifactsBucket=${AGENT_ARTIFACTS_BUCKET} AgentLockTable=${AGENT_LOCK_TABLE} AgentQueueUrl=${AGENT_QUEUE_URL} AgentQueueArn=${AGENT_QUEUE_ARN} ${OIDC_PROVIDER_PARAM:-} ${OIDC_ROLE_PARAM:-}"

# Compute the federated principal we intend to use for the IAM Role (helpful preview and validation)
FEDERATED_PRINCIPAL=""
if [ -n "${AGENT_OIDC_PROVIDER_HARDCODED_ARN:-}" ]; then
  FEDERATED_PRINCIPAL=${AGENT_OIDC_PROVIDER_HARDCODED_ARN}
elif [ -n "${AGENT_OIDC_PROVIDER_ARN:-}" ]; then
  FEDERATED_PRINCIPAL=${AGENT_OIDC_PROVIDER_ARN}
elif [ -n "${AGENT_OIDC_PROVIDER_DOMAIN:-}" ]; then
  FEDERATED_PRINCIPAL=${AGENT_OIDC_PROVIDER_DOMAIN}
elif [ -n "${EXISTING_OIDC_PROVIDER_ARN:-}" ]; then
  FEDERATED_PRINCIPAL=${EXISTING_OIDC_PROVIDER_ARN}
else
  # Assume we will create a provider in this account (domain token.actions.githubusercontent.com)
  if [ -n "${ACCOUNT_ID}" ]; then
    FEDERATED_PRINCIPAL="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
  fi
fi
echo "Federated principal that will be used for the role assume policy: ${FEDERATED_PRINCIPAL}"

# Ensure no unresolved CloudFormation placeholder remains in parameters or ARNs
for varname in AGENT_OIDC_PROVIDER_ARN AGENT_OIDC_PROVIDER_HARDCODED_ARN AGENT_OIDC_PROVIDER_DOMAIN AGENT_OIDC_ROLE_ARN AGENT_ROLE_ARN; do
  eval val="\"\${${varname}:-}\""
  if [[ "${val}" == *'${AWS::AccountId}'* || "${val}" == *"\$\{AWS::AccountId\}"* ]]; then
    echo "ERROR: Parameter ${varname} contains an unresolved \\${AWS::AccountId} placeholder: ${val}" >&2
    echo "Please substitute the account id (script will substitute if AWS credentials available), or pass domain-only (AGENT_OIDC_PROVIDER_DOMAIN) or an explicit ARN (AGENT_OIDC_PROVIDER_HARDCODED_ARN)." >&2
    exit 1
  fi
done

# DRY RUN: create and preview a change set for the OIDC stack rather than deploying it
if [ "$(echo "${DRY_RUN}" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
  echo "DRY_RUN is enabled: will create a CloudFormation change set for ${OIDC_STACK_NAME} and print proposed changes"
  # Determine change set type
  if aws_cmd cloudformation describe-stacks --stack-name "${OIDC_STACK_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    CHANGESET_TYPE=UPDATE
  else
    CHANGESET_TYPE=CREATE
  fi
  CS_NAME="preview-${OIDC_STACK_NAME}-$(date +%s)"
  echo "Creating change set ${CS_NAME} (Type: ${CHANGESET_TYPE})..."
  # Build parameter overrides list for create-change-set
  PARAMS=(ParameterKey=GitHubOwner,ParameterValue=${GH_OWNER} ParameterKey=GitHubRepo,ParameterValue=${GH_REPO} ParameterKey=AgentArtifactsBucket,ParameterValue=${AGENT_ARTIFACTS_BUCKET} ParameterKey=AgentLockTable,ParameterValue=${AGENT_LOCK_TABLE} ParameterKey=AgentQueueUrl,ParameterValue=${AGENT_QUEUE_URL} ParameterKey=AgentQueueArn,ParameterValue=${AGENT_QUEUE_ARN})
  if [ -n "${OIDC_PROVIDER_PARAM:-}" ]; then
    IFS='=' read -r pk pv <<<"${OIDC_PROVIDER_PARAM}"
    PARAMS+=(ParameterKey=${pk},ParameterValue=${pv})
  fi
  if [ -n "${OIDC_ROLE_PARAM:-}" ]; then
    # OIDC_ROLE_PARAM may contain two params
    for kv in ${OIDC_ROLE_PARAM}; do
      IFS='=' read -r pk pv <<<"${kv}"
      PARAMS+=(ParameterKey=${pk},ParameterValue=${pv})
    done
  fi
  CREATE_OUTPUT=$(aws_cmd cloudformation create-change-set --change-set-name "${CS_NAME}" --stack-name "${OIDC_STACK_NAME}" --region "${REGION}" --change-set-type ${CHANGESET_TYPE} --capabilities CAPABILITY_NAMED_IAM --template-body file://infra/agent-iam-oidc.yml --parameters "${PARAMS[@]}" 2>&1) || { echo "ERROR: failed to create change set: ${CREATE_OUTPUT}" >&2; exit 1; }
  echo "Waiting for change set to be created..."
  # Wait for completion (success or failed)
  aws_cmd cloudformation wait change-set-create-complete --change-set-name "${CS_NAME}" --stack-name "${OIDC_STACK_NAME}" --region "${REGION}" || true
  echo "Change set description:" && aws_cmd cloudformation describe-change-set --change-set-name "${CS_NAME}" --stack-name "${OIDC_STACK_NAME}" --region "${REGION}"
  echo "Change set changes (summary):" && aws_cmd cloudformation describe-change-set --change-set-name "${CS_NAME}" --stack-name "${OIDC_STACK_NAME}" --region "${REGION}" --query 'Changes[].ResourceChange' --output json
  echo "Deleting preview change set ${CS_NAME}..."
  aws_cmd cloudformation delete-change-set --change-set-name "${CS_NAME}" --stack-name "${OIDC_STACK_NAME}" --region "${REGION}" || true
  echo "DRY_RUN: preview complete; exiting without deploying." 
  exit 0
fi
if ! DEPLOY_OIDC_OUTPUT=$(aws_cmd cloudformation deploy \
  --template-file infra/agent-iam-oidc.yml \
  --stack-name "${OIDC_STACK_NAME}" \
  --region "${REGION}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides GitHubOwner=${GH_OWNER} GitHubRepo=${GH_REPO} AgentArtifactsBucket=${AGENT_ARTIFACTS_BUCKET} AgentLockTable=${AGENT_LOCK_TABLE} AgentQueueUrl=${AGENT_QUEUE_URL} AgentQueueArn=${AGENT_QUEUE_ARN} ${OIDC_PROVIDER_PARAM:-} ${OIDC_ROLE_PARAM:-} 2>&1); then
  echo "ERROR: CloudFormation deploy failed for ${OIDC_STACK_NAME}" >&2
  echo "--- aws deploy output ---" >&2
  echo "$DEPLOY_OIDC_OUTPUT" >&2
  if aws_cmd cloudformation describe-stacks --stack-name "${OIDC_STACK_NAME}" --region "${REGION}" >/dev/null 2>&1; then
    echo "--- CloudFormation OIDC stack events (recent) ---" >&2
    aws_cmd cloudformation describe-stack-events --stack-name "${OIDC_STACK_NAME}" --region "${REGION}" --max-items 20 --output json >&2 || true
  else
    echo "Stack ${OIDC_STACK_NAME} does not exist after deploy. Check permissions and role trust settings." >&2
  fi
  exit 2
fi

echo "OIDC stack deploy complete"

echo "CloudFormation stacks deployed. Outputs:"
if aws_cmd cloudformation describe-stacks --stack-name ${STACK_NAME} --region ${REGION} >/dev/null 2>&1; then
  echo "Stack outputs for ${STACK_NAME}:"
  aws_cmd cloudformation describe-stacks --stack-name ${STACK_NAME} --query 'Stacks[0].Outputs' --region ${REGION}
else
  echo "No stack outputs: ${STACK_NAME} doesn't exist in ${REGION}" >&2
fi
if aws_cmd cloudformation describe-stacks --stack-name ${OIDC_STACK_NAME} --region ${REGION} >/dev/null 2>&1; then
  echo "Stack outputs for ${OIDC_STACK_NAME}:"
  aws_cmd cloudformation describe-stacks --stack-name ${OIDC_STACK_NAME} --query 'Stacks[0].Outputs' --region ${REGION}
else
  echo "No stack outputs: ${OIDC_STACK_NAME} doesn't exist in ${REGION}" >&2
fi

