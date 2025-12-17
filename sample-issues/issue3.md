Add a new GET /api/health endpoint for health checks

This endpoint should:
1. Be accessible without authentication
2. Return HTTP 200 OK with a simple JSON response
3. Include application status information
4. Be useful for load balancers and monitoring systems

Example request:
GET /api/health

Example response (200 OK):
{
  "status": "UP",
  "timestamp": "2025-12-17T10:30:45Z",
  "version": "1.0.0",
  "environment": "production"
}

Additional requirements:
- Response time should be minimal (< 100ms)
- Should not require database access
- Should include application version info
