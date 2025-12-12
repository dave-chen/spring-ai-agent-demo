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


