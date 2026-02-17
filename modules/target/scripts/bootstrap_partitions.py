#!/usr/bin/env python3
"""
Bootstrap Glue partitions for existing CUR data.

This one-time script scans the S3 bucket for data files inside
timestamped assembly folders, groups them by billing period, and creates
Glue partitions pointing to the latest snapshot for each period.

After running, the Lambda function will keep partitions up-to-date
automatically.

Usage:
    # Configure these variables below before running:
    # - BUCKET: your aggregated CUR reports bucket name
    # - GLUE_DATABASE: your Glue database name
    # - GLUE_REGION: AWS region where Glue catalog lives
    # - ACCOUNTS: mapping of S3 prefix -> Glue table name

    export AWS_PROFILE=your-profile
    python3 bootstrap_partitions.py

Requires: boto3
"""

import re
from collections import defaultdict
import boto3

# =============================================================================
# Configuration - UPDATE THESE VALUES
# =============================================================================
BUCKET = "your-cur-reports-bucket"
GLUE_DATABASE = "cur_database"
GLUE_REGION = "eu-west-1"

# Map of S3 prefix -> Glue table name
# Example:
# ACCOUNTS = {
#     "account-prod/": "account_prod",
#     "account-dev/": "account_dev",
# }
ACCOUNTS = {}

# =============================================================================

s3 = boto3.client("s3", region_name=GLUE_REGION)
glue = boto3.client("glue", region_name=GLUE_REGION)

# Patterns
BILLING_PERIOD_RE = re.compile(r"\d{8}-\d{8}")
ASSEMBLY_RE = re.compile(r"\d{8}T\d{6}Z")


def find_partitions(prefix):
    """Find all billing periods under a prefix and determine partition locations.

    Handles both versioned CUR (timestamped assembly folders with Manifest.json)
    and overwrite CUR (data files directly in billing period folder).

    Returns dict of billing_period -> (label, partition_path).
    """
    paginator = s3.get_paginator("list_objects_v2")
    # For versioned CUR: billing_period -> list of (assembly_id, assembly_path)
    versioned = defaultdict(list)
    # For overwrite CUR: billing_period -> billing_period_path
    flat = {}

    for page in paginator.paginate(Bucket=BUCKET, Prefix=prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            parts = key.split("/")

            # Find billing period in path
            for i, part in enumerate(parts):
                if not BILLING_PERIOD_RE.fullmatch(part):
                    continue

                billing_period = part
                period_path = "/".join(parts[: i + 1])

                # Check if next part is a timestamped assembly (versioned CUR)
                if i + 1 < len(parts) and ASSEMBLY_RE.fullmatch(parts[i + 1]):
                    assembly_id = parts[i + 1]
                    assembly_path = "/".join(parts[: i + 2])
                    versioned[billing_period].append((assembly_id, assembly_path))
                elif key.endswith(".csv.gz"):
                    # Flat/overwrite CUR - data directly in billing period folder
                    flat[billing_period] = period_path
                break

    # Build result: prefer versioned (latest assembly), fallback to flat
    result = {}
    all_periods = set(versioned.keys()) | set(flat.keys())
    for period in all_periods:
        if period in versioned:
            assemblies = sorted(versioned[period], key=lambda x: x[0])
            latest_id, latest_path = assemblies[-1]
            result[period] = (latest_id, latest_path)
        else:
            result[period] = ("flat", flat[period])

    return result


def create_or_update_partition(table_name, billing_period, location):
    """Create or update a Glue partition."""
    table_response = glue.get_table(DatabaseName=GLUE_DATABASE, Name=table_name)
    sd = table_response["Table"]["StorageDescriptor"].copy()
    sd["Location"] = location

    partition_input = {
        "Values": [billing_period],
        "StorageDescriptor": sd,
    }

    try:
        glue.update_partition(
            DatabaseName=GLUE_DATABASE,
            TableName=table_name,
            PartitionValueList=[billing_period],
            PartitionInput=partition_input,
        )
        return "updated"
    except glue.exceptions.EntityNotFoundException:
        glue.create_partition(
            DatabaseName=GLUE_DATABASE,
            TableName=table_name,
            PartitionInput=partition_input,
        )
        return "created"


def main():
    if not ACCOUNTS:
        print("ERROR: Please configure ACCOUNTS mapping before running this script.")
        print("See the comments at the top of the file for instructions.")
        return

    for prefix, table_name in ACCOUNTS.items():
        print(f"\n{'='*60}")
        print(f"Processing {prefix} -> table '{table_name}'")
        print(f"{'='*60}")

        partitions = find_partitions(prefix)
        print(f"Found {len(partitions)} billing periods")

        for period in sorted(partitions.keys()):
            label, partition_path = partitions[period]
            location = f"s3://{BUCKET}/{partition_path}/"
            action = create_or_update_partition(table_name, period, location)
            print(f"  {period}: {action} -> {label}")

    print("\nDone!")


if __name__ == "__main__":
    main()
