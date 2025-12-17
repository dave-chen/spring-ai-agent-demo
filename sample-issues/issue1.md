Add a new POST /api/users endpoint for user creation

This endpoint should:
1. Accept a JSON payload with fields: name, email
2. Validate that email is in correct format
3. Return the created user object with an auto-generated id
4. Use HTTP 201 Created response status
5. Add appropriate error handling for invalid input

Example request:
POST /api/users
{
  "name": "John Doe",
  "email": "john@example.com"
}

Example response (201 Created):
{
  "id": 1,
  "name": "John Doe",
  "email": "john@example.com"
}

Error response for invalid email:
{
  "error": "Invalid email format",
  "status": 400
}
