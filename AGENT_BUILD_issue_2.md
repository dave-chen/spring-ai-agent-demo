Agent build for issue 2
Timestamp: 
Agent runtime id: not_set
Agent core output: Invoking AgentCore for issue 2 on repo dave-chen/spring-ai-agent-demo (runtime=, role=)
Invoking Claude API to generate code changes for issue 2
Fetching issue details from GitHub...
Issue #2: Test: Add hello world endpoint
Calling Claude API...
Endpoint: https://api.anthropic.com/v1/messages
Model: claude-3-sonnet-20240229
Request payload created. Sending to Claude API...
HTTP Status: 404
⚠️  Error: Claude API returned HTTP 404
Response: {"type":"error","error":{"type":"not_found_error","message":"model: claude-3-sonnet-20240229"},"request_id":"req_011CW8sADaXpvmABCTH3pZ3X"}
Error message: model: claude-3-sonnet-20240229
Claude agent invocation complete. Response saved to build/agent-artifacts/issue_2/
