Add a new DELETE /api/users/{id} endpoint to remove a user

This endpoint should:
1. Accept a path parameter {id} representing the user ID
2. Delete the user if they exist
3. Return HTTP 204 No Content on successful deletion
4. Return HTTP 404 Not Found if user doesn't exist
5. Include error messages for failures

Example request:
DELETE /api/users/1

Example response (204 No Content):
(empty body)

Error response when user not found (404):
{
  "error": "User not found",
  "status": 404
}

Additional considerations:
- Ensure proper cascade deletion of related records if applicable
- Consider adding soft delete option if audit trail is needed
- Add validation to prevent accidental bulk deletions
