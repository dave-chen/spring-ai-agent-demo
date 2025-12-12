# Agent Infra

This folder contains a simple CloudFormation template `agent-infra.yml` to create:
- An S3 bucket to store artifacts
- SQS FIFO queue for job messages
- DynamoDB table for locking
- An IAM role for the agent runtime

Deploy using the helper script:

```
AWS_REGION=us-east-1 ./scripts/infra-deploy.sh agent-infra-stack my-agent-artifacts-bucket-unique-123
```

The stack outputs include `AgentArtifactsBucket`, `AgentQueueUrl`, `AgentLockTable`, and `AgentRoleArn`.
