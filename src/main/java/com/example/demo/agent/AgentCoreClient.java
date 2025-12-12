package com.example.demo.agent;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
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
        ProcessBuilder pb = new ProcessBuilder("bash", "scripts/agent-core-invoke.sh", issueNumber, repo, runtimeId, roleArn);
        pb.redirectErrorStream(true);
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
