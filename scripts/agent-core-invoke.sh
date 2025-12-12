#!/usr/bin/env bash
set -eu

# Simple placeholder for invoking Bedrock AgentCore or Claude agent.
# This script should be replaced with actual Bedrock CLI/API integration.

ISSUE=${1:-}
REPO=${2:-}
RUNTIME_ID=${3:-}
ROLE_ARN=${4:-}

if [ -z "$ISSUE" ] || [ -z "$REPO" ]; then
  echo "Usage: agent-core-invoke.sh ISSUE_NUMBER REPO [RUNTIME_ID] [ROLE_ARN]"
  exit 1
fi

ARTIFACTS_DIR="build/agent-artifacts/issue_${ISSUE}"
mkdir -p "$ARTIFACTS_DIR"

echo "Invoking AgentCore for issue ${ISSUE} on repo ${REPO} (runtime=${RUNTIME_ID}, role=${ROLE_ARN})"

if [ -n "${USE_BEDROCK:-}" ] && [ -n "${RUNTIME_ID}" ]; then
  echo "Bedrock invocation configured (runtime=${RUNTIME_ID}) — invoking model via AWS CLI"
  # Construct a simple JSON payload requesting the agent to implement a plan
  PAYLOAD=$(jq -n --arg issue "$ISSUE" --arg repo "$REPO" '{input: "Implement feature for issue " + $issue + " in repo " + $repo}')
  if ! command -v aws >/dev/null 2>&1; then
    echo "aws CLI not found; please install aws CLI or set USE_BEDROCK to empty to simulate" >&2
    exit 2
  fi
  # Ensure AWS region is set
  AWS_REGION=${AWS_REGION:-us-east-1}
  OUTPUT=$(aws --region "$AWS_REGION" bedrock invoke-model --model-id "$RUNTIME_ID" --body "$PAYLOAD" --cli-binary-format raw-in-base64-out 2>&1) || {
    echo "Bedrock invocation failed: $OUTPUT" >&2
    exit 2
  }
  echo "Bedrock output: $OUTPUT"
  # Save output as an artifact
  mkdir -p "$ARTIFACTS_DIR"
  echo "$OUTPUT" > "$ARTIFACTS_DIR/bedrock_output_issue_${ISSUE}.json"
  echo "Done"
  exit 0
fi

if [ -n "${CLAUDE_API_KEY:-}" ] && [ -z "${USE_BEDROCK:-}" ]; then
  echo "Invoking Claude API for a plan"
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl not found; can't call Claude API" >&2
    exit 2
  fi
  # simple payload for Claude
  CLAUDE_PROMPT="Implement a build plan for issue ${ISSUE} in repo ${REPO}"
  CLAUDE_ENDPOINT=${CLAUDE_API_URL:-https://api.anthropic.com/v1/complete}
  RESPONSE=$(curl -s -X POST "$CLAUDE_ENDPOINT" \
    -H "x-api-key: ${CLAUDE_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"claude-2.1\", \"prompt\": \"${CLAUDE_PROMPT}\", \"max_tokens\": 1000}")
  mkdir -p "$ARTIFACTS_DIR"
  echo "$RESPONSE" > "$ARTIFACTS_DIR/claude_output_issue_${ISSUE}.json"
  echo "Claude response saved to $ARTIFACTS_DIR/claude_output_issue_${ISSUE}.json"
  exit 0
fi

echo "Simulating agent work: generating patch, screenshot, and test results..."
sleep 3

PATCH_FILE="${ARTIFACTS_DIR}/agent_changes_issue_${ISSUE}.patch"
SCREENSHOT_FILE="${ARTIFACTS_DIR}/screenshot_issue_${ISSUE}.png"
TEST_RESULT="${ARTIFACTS_DIR}/test_results_issue_${ISSUE}.txt"

echo "# Agent patch for issue ${ISSUE}" > "${PATCH_FILE}"
echo "(placeholder patch content)" >> "${PATCH_FILE}"
echo "(fake screenshot)" > "${SCREENSHOT_FILE}"
echo "All tests passed (simulated)" > "${TEST_RESULT}"

echo "{"
echo "  \"artifactDir\": \"${ARTIFACTS_DIR}\",
echo "  \"patchFile\": \"${PATCH_FILE}\",
echo "  \"screenshot\": \"${SCREENSHOT_FILE}\",
echo "  \"testResult\": \"${TEST_RESULT}\"
echo "}"

exit 0
