package com.example.demo.agent;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

public class ClaudeClient {
    private final String apiKey;
    private final HttpClient client = HttpClient.newHttpClient();
    private final ObjectMapper mapper = new ObjectMapper();

    public ClaudeClient(String apiKey) {
        this.apiKey = apiKey;
    }

    public String generatePlan(String prompt) throws IOException, InterruptedException {
        String endpoint = System.getenv().getOrDefault("CLAUDE_API_URL", "https://api.anthropic.com/v1/complete");
        String body = mapper.writeValueAsString(
                mapper.createObjectNode()
                        .put("model", "claude-2.1")
                        .put("prompt", prompt)
                        .put("max_tokens", 1000)
                        .toString()
        );
        HttpRequest req = HttpRequest.newBuilder()
                .uri(URI.create(endpoint))
                .header("x-api-key", apiKey)
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body))
                .build();
        HttpResponse<String> resp = client.send(req, HttpResponse.BodyHandlers.ofString());
        if (resp.statusCode() >= 200 && resp.statusCode() < 300) {
            JsonNode node = mapper.readTree(resp.body());
            if (node.has("completion")) {
                return node.get("completion").asText();
            }
            return resp.body();
        }
        throw new IOException("Claude API error: " + resp.statusCode() + " " + resp.body());
    }
}
