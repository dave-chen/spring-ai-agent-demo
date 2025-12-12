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

Prerequisites:
- Install the AWS CLI v2 (see https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html). On Ubuntu you can use:

```
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

- Install cfn-lint to lint CloudFormation templates (optional but recommended):

```
python -m pip install --user cfn-lint
```

Validate templates locally (optional):

```
./scripts/infra-validate.sh
```

Deploy the infra stack (noninteractive):

```
# Usage: scripts/infra-deploy.sh [STACK_NAME] [ARTIFACTS_BUCKET] [REGION] [GITHUB_OWNER] [GITHUB_REPO]
AWS_REGION=us-east-1 ./scripts/infra-deploy.sh agent-infra-stack my-agent-artifacts-bucket-unique-123 org-name repo-name
```

If your AWS account restricts creation of new IAM roles, pass an existing role ARN and the stack will not create a role:

```
AWS_REGION=us-east-1 ./scripts/infra-deploy.sh agent-infra-stack my-agent-artifacts-bucket-unique-123 org-name repo-name arn:aws:iam::970030241939:role/existing-agent-role
```

If you have a bucket or stack from a previous failed deploy, you can reuse the bucket and/or delete the old stack automatically:

 - Reuse existing IAM role: `ALLOW_EXISTING_ROLE=true` (useful when you already provisioned a role and want to reuse it; ensure `AGENT_ROLE_ARN` or allow the script to auto-detect the role ARN by name).

```
ALLOW_EXISTING_BUCKET=true DELETE_ROLLBACK_STACK=true AWS_REGION=us-east-1 ./scripts/infra-deploy.sh agent-infra-stack my-agent-artifacts-bucket-unique-123 org-name repo-name
```

Use a different AWS CLI profile to run the script (if you've created a new user and configured a profile):

```
AWS_PROFILE=my-new-profile AWS_REGION=us-east-1 ./scripts/infra-deploy.sh agent-infra-stack my-agent-artifacts-bucket-unique-123 org-name repo-name
```

Or, use STS to assume a role (script will use `jq` to parse assume-role output and export temporary credentials):

```
ASSUME_ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/my-deploy-role AWS_REGION=us-east-1 ./scripts/infra-deploy.sh agent-infra-stack my-agent-artifacts-bucket-unique-123 org-name repo-name
```

Note: The script will attempt to find an existing GitHub OIDC provider (https://token.actions.githubusercontent.com) in the account and reuse it. If you haven't created one and your account restricts creating OpenID Connect providers, create one manually or pass its ARN via an env var `AGENT_OIDC_PROVIDER_ARN`.
```
```

CloudFormation outputs will provide `AgentRoleArn`, `AgentArtifactsBucket`, `AgentQueueUrl`, and `AgentLockTable` names.

Set the following repo secrets (or store in AWS Secrets Manager) before running workflows:
- `AWS_REGION`
- `AWS_OIDC_ROLE_TO_ASSUME` (or use `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` temporarily)
 - `AWS_OIDC_ROLE_TO_ASSUME` (or use `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` temporarily)
 - `AGENT_OIDC_ROLE_ARN` (optional) — ARN of an existing GitHub OIDC role (gh-actions-agent-role-<repo>) to reuse; set when your account restricts role creation.
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



