# Agent Infra

This folder contains a simple CloudFormation template `agent-infra.yml` to create:
 - Reuse existing SQS Queue: `ALLOW_EXISTING_QUEUE=true` (useful when you have an existing FIFO queue you want to reuse). Pass a queue name; the script will query it.
 - Reuse existing IAM role: `ALLOW_EXISTING_ROLE=true` (useful when you have a pre-existing role to reuse). If you prefer the script to detect role ARN by name, set `ALLOW_EXISTING_ROLE=true`, otherwise specify `AGENT_ROLE_ARN` as the 6th argument.
- Install the AWS CLI v2 (see https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html).
- Install cfn-lint to lint CloudFormation templates (optional): `python -m pip install --user cfn-lint`.

Validate templates locally:

```
./scripts/infra-validate.sh
```

Deploy using the helper script (noninteractive):

```
AWS_REGION=us-east-1 ./scripts/infra-deploy.sh agent-infra-stack my-agent-artifacts-bucket-unique-123 org-name repo-name
```

If your AWS account restricts role creation, pass a pre-existing role ARN as a sixth argument to skip role creation:

```
AWS_REGION=us-east-1 ./scripts/infra-deploy.sh agent-infra-stack my-agent-artifacts-bucket-unique-123 org-name repo-name arn:aws:iam::970030241939:role/existing-agent-role

If you have an existing GitHub OIDC role (gh-actions-agent-role-<repo>) and want to reuse it rather than creating, set `AGENT_OIDC_ROLE_ARN` environment variable or pass it as the 11th argument to the script, and set `ALLOW_EXISTING_ROLE=true` if you want the script to auto-detect and reuse the role by name.
```

If you created a new AWS CLI profile, run using that profile:

```
AWS_PROFILE=my-devel-profile AWS_REGION=us-east-1 ./scripts/infra-deploy.sh agent-infra-stack my-agent-artifacts-bucket-unique-123 org-name repo-name
```

Or, assume a role with STS and run the script (script requires `jq`):

```
ASSUME_ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/my-deploy-role AWS_REGION=us-east-1 ./scripts/infra-deploy.sh agent-infra-stack my-agent-artifacts-bucket-unique-123 org-name repo-name
```

The stack outputs include `AgentArtifactsBucket`, `AgentQueueUrl`, `AgentLockTable`, and `AgentRoleArn`.
