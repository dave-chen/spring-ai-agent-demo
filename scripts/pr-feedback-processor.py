#!/usr/bin/env python3
"""
PR Feedback Processor

Monitors agent-generated PRs for comments containing @agent and 
dispatches feedback build to allow agent refinement.
"""

import os
import json
import re
import requests
import subprocess

GITHUB_TOKEN = os.environ.get('GITHUB_TOKEN')
REPO = os.environ.get('REPO')
FEEDBACK_TRIGGER = '@agent'

GITHUB_API = 'https://api.github.com'


def get_pr_from_event():
    """Extract PR info from GitHub event payload"""
    event_path = os.environ.get('GITHUB_EVENT_PATH')
    if not event_path or not os.path.exists(event_path):
        return None
    
    with open(event_path, 'r') as f:
        event = json.load(f)
    
    # Handle pull_request_review_comment events
    if 'pull_request' in event:
        return event['pull_request']['number']
    
    # Handle issue_comment events (could be PR comments)
    if event.get('issue', {}).get('pull_request'):
        return event['issue']['number']
    
    return None


def get_issue_from_pr(pr_number):
    """Extract original issue number from PR body"""
    headers = {'Authorization': f'token {GITHUB_TOKEN}'}
    url = f'{GITHUB_API}/repos/{REPO}/pulls/{pr_number}'
    
    try:
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()
        pr_data = response.json()
        
        # Look for issue reference in PR body
        body = pr_data.get('body', '')
        
        # Common patterns: "Closes #123", "Fixes #456", etc.
        match = re.search(r'(?:Closes|Fixes|Resolves|Related to|Issue|issue)\s*#(\d+)', body)
        if match:
            return int(match.group(1))
        
        # Also check the PR title
        title = pr_data.get('title', '')
        match = re.search(r'issue[_-](\d+)', title.lower())
        if match:
            return int(match.group(1))
        
        return None
    except Exception as e:
        print(f"Error getting PR details: {e}")
        return None


def get_feedback_from_comment():
    """Extract feedback text from the comment that triggered this"""
    event_path = os.environ.get('GITHUB_EVENT_PATH')
    if not event_path or not os.path.exists(event_path):
        return None
    
    with open(event_path, 'r') as f:
        event = json.load(f)
    
    comment_body = event.get('comment', {}).get('body', '')
    
    # Extract text after @agent mention
    if FEEDBACK_TRIGGER in comment_body:
        # Remove the @agent mention and get the rest
        feedback = comment_body.split(FEEDBACK_TRIGGER, 1)[1].strip()
        return feedback if feedback else "Please review and refine the implementation"
    
    return None


def dispatch_feedback_build(issue_number, pr_number, feedback):
    """Dispatch agent-feedback event to trigger re-build"""
    headers = {'Authorization': f'token {GITHUB_TOKEN}'}
    url = f'{GITHUB_API}/repos/{REPO}/dispatches'
    
    payload = {
        'event_type': 'agent-feedback',
        'client_payload': {
            'issue_number': issue_number,
            'pr_number': pr_number,
            'feedback': feedback,
            'lock_key': f'{REPO}_issue_{issue_number}'
        }
    }
    
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=10)
        response.raise_for_status()
        print(f"✓ Dispatched agent-feedback event for issue #{issue_number}, PR #{pr_number}")
        print(f"  Feedback: {feedback[:100]}...")
        return True
    except Exception as e:
        print(f"Error dispatching feedback event: {e}")
        return False


def main():
    """Main handler"""
    pr_number = get_pr_from_event()
    if not pr_number:
        print("No PR found in event")
        return
    
    print(f"Processing feedback for PR #{pr_number}")
    
    issue_number = get_issue_from_pr(pr_number)
    if not issue_number:
        print(f"Could not find issue reference in PR #{pr_number}")
        return
    
    print(f"Found related issue #{issue_number}")
    
    feedback = get_feedback_from_comment()
    if not feedback:
        print("No feedback found in comment")
        return
    
    print(f"Feedback: {feedback}")
    
    # Dispatch the feedback build
    dispatch_feedback_build(issue_number, pr_number, feedback)


if __name__ == '__main__':
    main()
