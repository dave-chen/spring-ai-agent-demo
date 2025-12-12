package com.example.demo.agent;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.time.Duration;
import java.util.UUID;

import software.amazon.awssdk.auth.credentials.AwsCredentials;
import software.amazon.awssdk.auth.credentials.AwsSessionCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.services.sts.StsClient;
import software.amazon.awssdk.services.sts.model.AssumeRoleRequest;
import software.amazon.awssdk.services.sts.model.AssumeRoleResponse;
import java.util.HashMap;
import java.util.Map;

public class AgentCoreClient {
    private final String runtimeId;
    private final String roleArn;

    public AgentCoreClient(String runtimeId, String roleArn) {
        this.runtimeId = runtimeId;
        this.roleArn = roleArn;
    }

    /**
     * Starts the agent via an external script (placeholder for AWS Bedrock AgentCore invocation).
     * Returns a simple execution result map with status and artifact path.
     */
    public Map<String, String> startAgent(String issueNumber, String repo) throws IOException, InterruptedException {
        // If roleArn is provided, attempt to assume role and export temporary creds to script environment
        String agentRoleAccessKey = null;
        String agentRoleSecret = null;
        String agentRoleSessionToken = null;
        if (this.roleArn != null && !this.roleArn.isBlank()) {
            try (StsClient sts = StsClient.create()) {
                AssumeRoleRequest req = AssumeRoleRequest.builder()
                        .roleArn(this.roleArn)
                        .roleSessionName("agent-session-" + UUID.randomUUID())
                        .durationSeconds(900)
                        .build();
                AssumeRoleResponse resp = sts.assumeRole(req);
                var c = resp.credentials();
                agentRoleAccessKey = c.accessKeyId();
                agentRoleSecret = c.secretAccessKey();
                agentRoleSessionToken = c.sessionToken();
            } catch (Exception e) {
                // fall through, script will run with existing env
            }
        }
        ProcessBuilder pb = new ProcessBuilder("bash", "scripts/agent-core-invoke.sh", issueNumber, repo, runtimeId, roleArn);
        pb.redirectErrorStream(true);
        if (agentRoleAccessKey != null) {
            Map<String, String> env = pb.environment();
            env.put("AWS_ACCESS_KEY_ID", agentRoleAccessKey);
            env.put("AWS_SECRET_ACCESS_KEY", agentRoleSecret);
            env.put("AWS_SESSION_TOKEN", agentRoleSessionToken);
        }
        Process p = pb.start();
        StringBuilder output = new StringBuilder();
        try (BufferedReader rdr = new BufferedReader(new InputStreamReader(p.getInputStream()))) {
            String line;
            while ((line = rdr.readLine()) != null) {
                output.append(line).append("\n");
            }
        }
        int rc = p.waitFor();
        Map<String, String> result = new HashMap<>();
        result.put("exitCode", String.valueOf(rc));
        result.put("output", output.toString());
        // Agent should write artifact path (if any) to stdout; a real impl would return structured JSON
        return result;
    }
}
