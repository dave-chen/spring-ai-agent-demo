Agent build for issue 1
Timestamp: 
Agent runtime id: not_set
Agent core output: Invoking AgentCore for issue 1 on repo dave-chen/spring-ai-agent-demo (runtime=, role=)
Invoking Claude API to generate code changes for issue 1
Fetching issue details from GitHub...
Issue #1: Test Agent Build
Calling Claude API...
Endpoint: https://api.anthropic.com/v1/messages
Model: claude-3-5-sonnet-20241022
Request payload created. Sending to Claude API...
HTTP Status: 400
⚠️  Error: Claude API returned HTTP 400
Response: {"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits."},"request_id":"req_011CW7ofE7cZQdw3jj86TEwh"}
Error message: Your credit balance is too low to access the Anthropic API. Please go to Plans & Billing to upgrade or purchase credits.
Claude agent invocation complete. Response saved to build/agent-artifacts/issue_1/
