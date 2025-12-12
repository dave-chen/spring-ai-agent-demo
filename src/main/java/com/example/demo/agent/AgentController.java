package com.example.demo.agent;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AgentController {

    @Value("${agentcore.runtime-id:}")
    private String runtimeId;

    @Value("${agentcore.role-arn:}")
    private String roleArn;

    @Value("${GITHUB_REPOSITORY:}")
    private String githubRepo;

    @PostMapping("/api/agent/build")
    public ResponseEntity<?> buildIssue(@RequestParam("issue") String issueNumber, @RequestParam(value = "repo", required = false) String repo) {
        if (repo == null || repo.isBlank()) {
            repo = githubRepo;
        }
        AgentCoreClient client = new AgentCoreClient(runtimeId, roleArn);
        AgentService service = new AgentService(client);
        AgentService.BuildResult result = service.runAgentForIssue(issueNumber, repo);
        return ResponseEntity.ok(result);
    }
}
