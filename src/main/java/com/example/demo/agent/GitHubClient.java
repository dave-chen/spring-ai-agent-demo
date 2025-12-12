package com.example.demo.agent;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;

public class GitHubClient {
    private final String repo;
    private final String token;
    private final HttpClient client = HttpClient.newHttpClient();

    public GitHubClient(String repo, String token) {
        this.repo = repo;
        this.token = token;
    }

    public int createPullRequest(String head, String base, String title, String body) throws IOException, InterruptedException {
        String uri = String.format("https://api.github.com/repos/%s/pulls", repo);
        String payload = String.format("{\"title\":\"%s\",\"head\":\"%s\",\"base\":\"%s\",\"body\":\"%s\"}", title, head, base, body);
        HttpRequest request = HttpRequest.newBuilder()
                .uri(URI.create(uri))
                .header("Authorization", "Bearer " + token)
                .header("Accept", "application/vnd.github+json")
                .POST(HttpRequest.BodyPublishers.ofString(payload))
                .build();
        HttpResponse<String> resp = client.send(request, HttpResponse.BodyHandlers.ofString());
        return resp.statusCode();
    }
}
