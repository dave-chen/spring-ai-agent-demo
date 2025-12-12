package com.example.demo.agent;

import java.io.IOException;
import java.util.Map;

public class AgentService {
    private final AgentCoreClient agentCoreClient;

    public AgentService(AgentCoreClient agentCoreClient) {
        this.agentCoreClient = agentCoreClient;
    }

    public BuildResult runAgentForIssue(String issueNumber, String repo) {
        try {
            Map<String, String> res = agentCoreClient.startAgent(issueNumber, repo);
            int exit = Integer.parseInt(res.getOrDefault("exitCode", "1"));
            String output = res.getOrDefault("output", "");
            return new BuildResult(exit == 0, output);
        } catch (IOException | InterruptedException e) {
            return new BuildResult(false, e.getMessage());
        }
    }

    public static class BuildResult {
        public final boolean success;
        public final String details;

        public BuildResult(boolean success, String details) {
            this.success = success;
            this.details = details;
        }
    }
}
