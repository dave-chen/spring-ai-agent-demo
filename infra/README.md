# Agent Infra

This folder contains a simple CloudFormation template `agent-infra.yml` to create:
- An S3 bucket to store artifacts
- SQS FIFO queue for job messages
- DynamoDB table for locking
- An IAM role for the agent runtime

Prerequisites:
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
```

The stack outputs include `AgentArtifactsBucket`, `AgentQueueUrl`, `AgentLockTable`, and `AgentRoleArn`.
