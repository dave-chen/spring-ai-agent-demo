#!/usr/bin/env bash
set -eu

# Simple infra validation script. Lints CloudFormation templates using cfn-lint
# and optionally runs aws cloudformation validate-template if the aws CLI is present.

check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "false"
  else
    echo "true"
  fi
}

TEMPLATES=(infra/agent-infra.yml infra/agent-iam-oidc.yml)

# Check cfn-lint
if [ "$(check_command cfn-lint)" = "true" ]; then
  echo "Running cfn-lint on templates..."
  for t in "${TEMPLATES[@]}"; do
    echo "Linting ${t}"
    cfn-lint "${t}"
  done
else
  echo "cfn-lint not found. Install it with: pip install --user cfn-lint"
fi

# Check aws CLI and run validate-template if present
if [ "$(check_command aws)" = "true" ]; then
  echo "AWS CLI found. Running cloudformation validate-template..."
  for t in "${TEMPLATES[@]}"; do
    echo "Validating ${t} via AWS CloudFormation"
    aws cloudformation validate-template --template-body file://${t} || echo "AWS validate-template failed for ${t}"
  done
else
  echo "aws CLI not found. Install it before running 'aws cloudformation validate-template': https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
fi

echo "Validation complete."
