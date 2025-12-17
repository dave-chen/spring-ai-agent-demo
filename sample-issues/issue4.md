Add request logging middleware for all API endpoints

This middleware should:
1. Log all incoming HTTP requests with method, path, and timestamp
2. Log response status code and response time
3. Log request payload size and response payload size
4. Use appropriate log levels (INFO for successful requests, WARN/ERROR for failures)
5. Not log sensitive information (passwords, tokens)

Example log output:
[2025-12-17 10:30:45] INFO: POST /api/users - 201 Created (45ms) - Request: 256B, Response: 128B

Requirements:
- Use Spring's built-in logging framework
- Make it configurable via application.properties
- Should have minimal performance impact
- Include exception logging for errors
