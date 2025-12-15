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
  # Upload artifacts to S3 if bucket provided
  if [ -n "${AGENT_ARTIFACTS_BUCKET:-}" ]; then
    if command -v aws >/dev/null 2>&1; then
      echo "Uploading artifacts to s3://${AGENT_ARTIFACTS_BUCKET}/issues/${ISSUE}/"
      aws s3 cp "$ARTIFACTS_DIR/" "s3://${AGENT_ARTIFACTS_BUCKET}/issues/${ISSUE}/" --recursive || echo "s3 upload failed"
    else
      echo "Warning: AGENT_ARTIFACTS_BUCKET set but aws CLI not found; skipping upload"
    fi
  fi
  echo "Done"
  exit 0
fi

if [ -n "${CLAUDE_API_KEY:-}" ] && [ -z "${USE_BEDROCK:-}" ]; then
  echo "Invoking Claude API to generate code changes for issue ${ISSUE}"
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl not found; can't call Claude API" >&2
    exit 2
  fi
  
  # Fetch issue details from GitHub
  echo "Fetching issue details from GitHub..."
  ISSUE_DATA=$(curl -s -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN:-}" \
    "https://api.github.com/repos/${REPO}/issues/${ISSUE}")
  
  ISSUE_TITLE=$(echo "$ISSUE_DATA" | jq -r '.title // "Unknown"')
  ISSUE_BODY=$(echo "$ISSUE_DATA" | jq -r '.body // "No description"')
  
  echo "Issue #${ISSUE}: ${ISSUE_TITLE}"
  
  # Build Claude prompt
  CLAUDE_PROMPT="You are a software developer working on the repository ${REPO}. 

Issue #${ISSUE}: ${ISSUE_TITLE}

Description:
${ISSUE_BODY}

Please generate the code changes needed to implement this feature. Provide:
1. Complete, working code files (not just snippets)
2. Clear explanations of what was changed
3. Any test cases if applicable

Focus on Spring Boot Java applications. Be specific and complete in your implementation."

  # Use Claude Messages API (current format)
  CLAUDE_ENDPOINT="https://api.anthropic.com/v1/messages"
  
  echo "Calling Claude API..."
  echo "Endpoint: $CLAUDE_ENDPOINT"
  echo "Model: claude-3-5-sonnet-20241022"
  
  # Create the request payload
  PAYLOAD=$(jq -n --arg prompt "$CLAUDE_PROMPT" '{
    model: "claude-3-5-sonnet-20241022",
    max_tokens: 4096,
    messages: [{
      role: "user",
      content: $prompt
    }]
  }')
  
  echo "Request payload created. Sending to Claude API..."
  
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$CLAUDE_ENDPOINT" \
    -H "x-api-key: ${CLAUDE_API_KEY}" \
    -H "anthropic-version: 2023-06-01" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")
  
  # Extract HTTP status code (last line)
  HTTP_STATUS=$(echo "$RESPONSE" | tail -n1)
  # Get response body (everything except last line)
  RESPONSE_BODY=$(echo "$RESPONSE" | head -n-1)
  
  echo "HTTP Status: $HTTP_STATUS"
  
  mkdir -p "$ARTIFACTS_DIR"
  echo "$RESPONSE_BODY" > "$ARTIFACTS_DIR/claude_output_issue_${ISSUE}.json"
  
  # Check if response was successful
  if [ "$HTTP_STATUS" -ne 200 ]; then
    echo "⚠️  Error: Claude API returned HTTP $HTTP_STATUS"
    echo "Response: $RESPONSE_BODY"
    # Still try to extract error message
    ERROR_MSG=$(echo "$RESPONSE_BODY" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
    echo "Error message: $ERROR_MSG"
    
    # Save error to artifact file and continue
    echo "Claude API Error (HTTP $HTTP_STATUS):" > "$ARTIFACTS_DIR/claude_response_issue_${ISSUE}.txt"
    echo "$ERROR_MSG" >> "$ARTIFACTS_DIR/claude_response_issue_${ISSUE}.txt"
    echo "" >> "$ARTIFACTS_DIR/claude_response_issue_${ISSUE}.txt"
    echo "Full Response:" >> "$ARTIFACTS_DIR/claude_response_issue_${ISSUE}.txt"
    echo "$RESPONSE_BODY" >> "$ARTIFACTS_DIR/claude_response_issue_${ISSUE}.txt"
  else
    # Extract the response text
    CLAUDE_TEXT=$(echo "$RESPONSE_BODY" | jq -r '.content[0].text // "Error: No response"')
    echo "$CLAUDE_TEXT" > "$ARTIFACTS_DIR/claude_response_issue_${ISSUE}.txt"
    
    echo "Claude response:"
    echo "$CLAUDE_TEXT"
  fi
  
  if [ -n "${AGENT_ARTIFACTS_BUCKET:-}" ]; then
    if command -v aws >/dev/null 2>&1; then
      echo "Uploading artifacts to s3://${AGENT_ARTIFACTS_BUCKET}/issues/${ISSUE}/"
      aws s3 cp "$ARTIFACTS_DIR/" "s3://${AGENT_ARTIFACTS_BUCKET}/issues/${ISSUE}/" --recursive || echo "s3 upload failed"
    else
      echo "Warning: AGENT_ARTIFACTS_BUCKET set but aws CLI not found; skipping upload"
    fi
  fi
  echo "Claude agent invocation complete. Response saved to $ARTIFACTS_DIR/"
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
