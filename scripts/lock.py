#!/usr/bin/env python3
"""
Lock helper using DynamoDB. The table name is read from env var LOCK_TABLE_NAME.
Requires AWS credentials in environment (or role via OIDC).

Operations:
  - acquire --lock-key KEY --ttl-minutes N
  - release --lock-key KEY
"""
import os
import sys
import time
import argparse
import boto3
from botocore.exceptions import ClientError

LOCK_TABLE = os.environ.get("LOCK_TABLE_NAME", "AgentLockTable")

def acquire(lock_key: str, ttl_minutes: int):
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table(LOCK_TABLE)
    expires = int(time.time()) + ttl_minutes * 60
    try:
        table.put_item(
            Item={
                'lockKey': lock_key,
                'expiresAt': expires,
                'owner': os.environ.get('GITHUB_RUN_ID', 'agent-runner'),
            },
            ConditionExpression='attribute_not_exists(lockKey)'
        )
        print(f"Lock acquired: {lock_key}")
        return 0
    except ClientError as e:
        if e.response['Error']['Code'] == 'ConditionalCheckFailedException':
            print(f"Could not acquire lock (already exists): {lock_key}")
            return 1
        else:
            raise

def release(lock_key: str):
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table(LOCK_TABLE)
    try:
        table.delete_item(Key={'lockKey': lock_key})
        print(f"Lock released: {lock_key}")
        return 0
    except ClientError as e:
        print(f"Failed to release lock: {e}")
        return 1

def parse_args():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='cmd')
    acq = sub.add_parser('acquire')
    acq.add_argument('--lock-key', required=True)
    acq.add_argument('--ttl-minutes', default=30, type=int)
    rel = sub.add_parser('release')
    rel.add_argument('--lock-key', required=True)
    return parser.parse_args()

def main():
    args = parse_args()
    if args.cmd == 'acquire':
        sys.exit(acquire(args.lock_key, args.ttl_minutes))
    if args.cmd == 'release':
        sys.exit(release(args.lock_key))

if __name__ == '__main__':
    main()
