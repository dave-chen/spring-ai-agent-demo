Add a new GET /api/users/{id} endpoint to retrieve user by ID

This endpoint should:
1. Accept a path parameter {id} representing the user ID
2. Return the user object if found
3. Return HTTP 404 Not Found if user doesn't exist
4. Include proper error message in the response

Example request:
GET /api/users/1

Example response (200 OK):
{
  "id": 1,
  "name": "John Doe",
  "email": "john@example.com"
}

Error response when user not found (404):
{
  "error": "User not found",
  "status": 404
}

Note: You may need to create a User model/entity class if it doesn't exist yet.
