#!/usr/bin/env python3
"""
Poll the GitHub repo for issues labeled 'autobuild', check reactions, and dispatch approved issues.

Environment variables:
  - GITHUB_TOKEN: token with repo permissions
  - REPO: owner/repo
  - AGENT_APPROVERS: comma-separated list of GitHub logins that can approve (rocket reaction)
"""
import os
import requests
import sys
from urllib.parse import quote_plus

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN")
REPO = os.environ.get("REPO")
APPROVERS = os.environ.get("AGENT_APPROVERS", "").split(",") if os.environ.get("AGENT_APPROVERS") else []

if not GITHUB_TOKEN or not REPO:
    print("Please set GITHUB_TOKEN and REPO environment variables.")
    sys.exit(1)

API = "https://api.github.com"
HEADERS = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {GITHUB_TOKEN}",
    "X-GitHub-Api-Version": "2022-11-28",
}

def get_autobuild_issues():
    # Get open issues labeled 'autobuild'
    url = f"{API}/repos/{REPO}/issues?labels=autobuild&state=open"
    r = requests.get(url, headers=HEADERS)
    r.raise_for_status()
    return r.json()

def get_reactions(issue_number):
    url = f"{API}/repos/{REPO}/issues/{issue_number}/reactions"
    r = requests.get(url, headers={**HEADERS, "Accept": "application/vnd.github.squirrel-girl-preview+json"})
    r.raise_for_status()
    return r.json()

def dispatch_build(issue_number, votes):
    url = f"{API}/repos/{REPO}/dispatches"
    payload = {
        "event_type": "agent-build",
        "client_payload": {
            "issue_number": issue_number,
            "votes": votes,
            "lock_key": f"{REPO.replace('/', '_')}_issue_{issue_number}",
        },
    }
    r = requests.post(url, headers=HEADERS, json=payload)
    r.raise_for_status()
    print(f"Dispatched build for issue #{issue_number}")

def is_authorized(reaction_user):
    if not APPROVERS:
        # If no approvers set, allow any user for demo
        return True
    return reaction_user in APPROVERS

def main():
    issues = get_autobuild_issues()
    candidates = []
    for issue in issues:
        number = issue["number"]
        reactions = get_reactions(number)
        plus_one_count = 0
        authorized = False
        for r in reactions:
            if r.get("content") == "+1":
                plus_one_count += 1
            if r.get("content") == "rocket":
                user = r.get("user", {}).get("login")
                if is_authorized(user):
                    authorized = True
        if authorized:
            candidates.append((number, plus_one_count))
        else:
            print(f"Issue #{number} not approved (authorized rocket) — skipping")

    # Sort by votes (desc) and dispatch highest-priority items
    candidates.sort(key=lambda x: x[1], reverse=True)
    for number, votes in candidates:
        print(f"Issue #{number} approved and prioritized ({votes} votes) — dispatching")
        dispatch_build(number, votes)

if __name__ == "__main__":
    main()
