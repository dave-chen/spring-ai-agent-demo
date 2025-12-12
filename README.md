# spring-ai-agent-demo

A simple Spring Boot demo project using Gradle and Java 21.

Run the app:

- Build: `gradle build` (or `./gradlew build` if you have a wrapper).
- Run: `gradle bootRun` (or `./gradlew bootRun`).
- Test: `gradle test` (or `./gradlew test`).

Endpoint:

- `GET /api/hello` — returns a friendly message.

Example:

```
curl http://localhost:8080/api/hello
```

Agent automation summary:

- Add GH secrets: `AWS_REGION`, `AWS_OIDC_ROLE_TO_ASSUME`, `AGENT_APPROVERS`, `AGENTCORE_RUNTIME_ID`, `AGENTCORE_ROLE_ARN`.
- Poll GitHub Issues with label `autobuild` using `.github/workflows/issue-poller.yml`.
- Agent build workflow triggers on `repository_dispatch` and runs scripts/agent-build.sh, acquiring locks using DynamoDB defined in `infra/lock-table.yml`.

Scripts:
- `scripts/issue-poller.py` — Polls issues, checks reactions, dispatches builds.
- `scripts/agent-build.sh` — A placeholder to create an agent runtime branch and open PRs.
- `scripts/lock.py` — Acquire/release lock using `AgentLockTable`.

Notes:
- This first implementation adds the skeleton workflows and scripts; you need to provide suppying secrets and an AWS role/permissions for assuming role via OIDC.
- Integration with AWS Bedrock AgentCore and Claude SDK will be added in subsequent steps — placeholders are in `scripts/agent-build.sh`.

Deploy infra (example):

```
# Create an artifacts bucket and deploy the infra stack
AWS_REGION=us-east-1 ./scripts/infra-deploy.sh agent-infra-stack my-agent-artifacts-bucket-unique-123
```

CloudFormation outputs will provide `AgentRoleArn`, `AgentArtifactsBucket`, `AgentQueueUrl`, and `AgentLockTable` names.

Set the following repo secrets (or store in AWS Secrets Manager) before running workflows:
- `AWS_REGION`
- `AWS_OIDC_ROLE_TO_ASSUME` (or use `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` temporarily)
- `AGENT_APPROVERS` (comma-separated logins allowed to approve)
- `AGENTCORE_RUNTIME_ID` and `AGENTCORE_ROLE_ARN`

Secrets matrix (example):
 - `AWS_REGION=us-east-1`
 - `AGENT_APPROVERS=alice,bob` (user logins)
 - `AGENT_APPROVER_TEAMS=org1/core-team,org1/infra-team` (org/team_slug pairs)
 - `AGENT_ARTIFACTS_BUCKET` (S3 bucket), `AGENT_QUEUE_URL`, `LOCK_TABLE_NAME`
 - `CLAUDE_API_KEY` (if using Claude directly)
 - `AGENTCORE_RUNTIME_ID` and `AGENTCORE_ROLE_ARN` (if using Bedrock)
 - `AWS_OIDC_ROLE_TO_ASSUME` (role to assume in Actions via OIDC)
 - `CLOUDFRONT_DIST_ID` (optional)

CloudFormation deploy commands (example):

```
# 1) Deploy agent infra (S3, SQS, DynamoDB, IAM role)
AWS_REGION=us-east-1 ./scripts/infra-deploy.sh agent-infra-stack my-agent-artifacts-bucket-unique-123

# 2) Deploy OIDC role stack (this runs automatically in infra-deploy.sh)
# Outputs will be printed that include: AgentArtifactsBucket, AgentQueueUrl, AgentLockTable, AgentRoleArn, GitHubOIDCRoleArn

# 3) Copy outputs into GitHub secrets (or use OIDC for AWS creds):
# - AGENT_ARTIFACTS_BUCKET=MyArtifactsBucketName
# - AGENT_QUEUE_URL=sqs://example
# - LOCK_TABLE_NAME=AgentLockTable
# - AWS_OIDC_ROLE_TO_ASSUME=arn:aws:iam::<account-id>:role/gh-actions-agent-role-<repo>
# - AGENT_APPROVER_TEAMS=org1/team1,org1/team2
```

Triggering agent manually (local dev):

```
# Start the Spring Boot app
./gradlew bootRun

# Trigger an agent build via HTTP API (requires app running on port 8080)
curl -X POST "http://localhost:8080/api/agent/build?issue=123&repo=dave-chen/spring-ai-agent-demo"
```

GitHub token and permissions: Ensure `GITHUB_TOKEN` or your selected token has `read:org` permission (or install a GitHub App) so the poller can validate team membership for approvals.



