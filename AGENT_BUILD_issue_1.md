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
HTTP Status: 404
⚠️  Error: Claude API returned HTTP 404
Response: {"type":"error","error":{"type":"not_found_error","message":"model: claude-3-5-sonnet-20241022"},"request_id":"req_011CW8rTZArhwL1zuHB4H1BE"}
Error message: model: claude-3-5-sonnet-20241022
Claude agent invocation complete. Response saved to build/agent-artifacts/issue_1/
