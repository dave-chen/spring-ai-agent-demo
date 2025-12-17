#!/bin/bash
# Script to create demo GitHub issues from sample-issues folder

set -e

REPO="${1:-}"
if [ -z "$REPO" ]; then
  echo "Usage: ./create-demo-issues.sh <owner/repo>"
  echo "Example: ./create-demo-issues.sh dave-chen/spring-ai-agent-demo"
  exit 1
fi

echo "Creating demo issues for $REPO..."
echo ""

ISSUES_DIR="sample-issues"
ISSUE_COUNT=0

for issue_file in "$ISSUES_DIR"/issue*.md; do
  if [ ! -f "$issue_file" ]; then
    echo "No issue files found in $ISSUES_DIR/"
    exit 1
  fi

  # Extract title (first line)
  TITLE=$(head -n 1 "$issue_file")
  
  echo "Creating issue: $TITLE"
  
  # Create issue with autobuild label
  gh issue create \
    --repo "$REPO" \
    --title "$TITLE" \
    --body-file "$issue_file" \
    --label "autobuild"
  
  ISSUE_COUNT=$((ISSUE_COUNT + 1))
  echo "✅ Created issue #$ISSUE_COUNT"
  echo ""
  
  # Small delay to avoid rate limiting
  sleep 1
done

echo "✅ Created $ISSUE_COUNT demo issues!"
echo ""
echo "Next steps:"
echo "1. Start your self-hosted runner: cd ~/actions-runner && ./run.sh"
echo "2. Go to https://github.com/$REPO/actions/workflows/issue-poller.yml"
echo "3. Click 'Run workflow' to trigger the agent"
echo "4. Watch the agent generate PRs for the issues!"
