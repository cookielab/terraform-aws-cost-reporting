"""
Lambda function to forward CUR (Cost and Usage Report) files to another S3 bucket.

This function is triggered by S3 events when new CUR files are uploaded.
It supports both direct S3 events and SNS-wrapped S3 events.
It copies the files to a destination bucket in another AWS account.

When a Manifest.json is detected inside a timestamped assembly folder,
the function also copies all referenced data files from the manifest and
updates the corresponding Athena/Glue partition to point to the latest
snapshot, ensuring queries only see the most recent data.
"""

import os
import json
import logging
import re
import urllib.parse
import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')

DESTINATION_BUCKET = os.environ.get('DESTINATION_BUCKET')
PREFIX_MAPPING = json.loads(os.environ.get('PREFIX_MAPPING', '{}'))

# Athena partition management config
GLUE_DATABASE = os.environ.get('GLUE_DATABASE', '')
GLUE_REGION = os.environ.get('GLUE_REGION', 'eu-west-1')
TABLE_MAPPING = json.loads(os.environ.get('TABLE_MAPPING', '{}'))

_glue_client = None


def get_glue_client():
    """Get Glue client for the region where the Glue catalog lives."""
    global _glue_client
    if _glue_client is None:
        _glue_client = boto3.client('glue', region_name=GLUE_REGION)
    return _glue_client


def handler(event, context):
    """Lambda handler for S3 event notifications (direct or SNS-wrapped)."""
    logger.info(f"Received event: {event}")

    if not DESTINATION_BUCKET:
        logger.error("DESTINATION_BUCKET environment variable is not set")
        raise ValueError("DESTINATION_BUCKET environment variable is required")

    processed_files = []
    errors = []

    for record in event.get('Records', []):
        try:
            # Check if this is an SNS-wrapped S3 event
            if 'Sns' in record:
                logger.info("Processing SNS-wrapped S3 event")
                sns_message = json.loads(record['Sns']['Message'])
                # Process each S3 record within the SNS message
                for s3_record in sns_message.get('Records', []):
                    result = process_record(s3_record)
                    processed_files.append(result)
            else:
                # Direct S3 event
                logger.info("Processing direct S3 event")
                result = process_record(record)
                processed_files.append(result)
        except Exception as e:
            error_msg = f"Error processing record: {e}"
            logger.error(error_msg)
            errors.append(error_msg)

    response = {
        'statusCode': 200 if not errors else 207,
        'processed': len(processed_files),
        'errors': len(errors),
        'files': processed_files
    }

    if errors:
        response['error_details'] = errors

    logger.info(f"Completed processing: {response}")
    return response


def process_record(record):
    """Process a single S3 event record."""
    source_bucket = record['s3']['bucket']['name']
    source_key = urllib.parse.unquote_plus(record['s3']['object']['key'])

    logger.info(f"Processing file: s3://{source_bucket}/{source_key}")

    # Get prefix configuration for this source bucket
    prefix_config = PREFIX_MAPPING.get(source_bucket, {})
    if not prefix_config:
        logger.warning(f"No prefix mapping found for bucket {source_bucket}, using defaults")
        prefix_config = {'source_prefix': '', 'destination_prefix': ''}

    destination_key = calculate_destination_key(source_key, prefix_config)

    # If this is an assembly manifest, don't copy it to destination - Athena would
    # try to parse the JSON as CSV, breaking CAST operations. Instead, read it from
    # the source bucket and copy all referenced data files.
    copied_data_files = []
    if is_assembly_manifest(destination_key):
        logger.info(f"Assembly manifest detected, copying data files (not the manifest): {destination_key}")
        copied_data_files = copy_manifest_data_files(
            source_bucket, source_key, prefix_config
        )
    else:
        logger.info(f"Copying to: s3://{DESTINATION_BUCKET}/{destination_key}")
        copy_object(source_bucket, source_key, DESTINATION_BUCKET, destination_key)

    # After copying, try to update the Athena partition.
    # Trigger on manifest events (SNS-based accounts) or data file events
    # (S3-event-based accounts). The key is used only for path parsing
    # (table name, billing period, assembly folder) - works with any key
    # in the assembly folder.
    if GLUE_DATABASE:
        partition_key = None
        if is_assembly_manifest(destination_key):
            partition_key = destination_key
        elif is_assembly_data_file(destination_key):
            partition_key = destination_key

        if partition_key:
            try:
                update_athena_partition(DESTINATION_BUCKET, partition_key)
            except Exception as e:
                # Don't raise - file copy succeeded, partition update is best-effort
                logger.error(f"Failed to update Athena partition: {e}")

    result = {
        'source': f"s3://{source_bucket}/{source_key}",
        'destination': f"s3://{DESTINATION_BUCKET}/{destination_key}"
    }
    if copied_data_files:
        result['copied_data_files'] = len(copied_data_files)
    return result


def calculate_destination_key(source_key, prefix_config):
    """Calculate the destination key based on source key and configured prefixes."""
    source_prefix = prefix_config.get('source_prefix', '')
    destination_prefix = prefix_config.get('destination_prefix', '')

    relative_key = source_key
    if source_prefix and source_key.startswith(source_prefix):
        relative_key = source_key[len(source_prefix):]
        relative_key = relative_key.lstrip('/')

    if destination_prefix:
        destination_key = f"{destination_prefix.rstrip('/')}/{relative_key}"
    else:
        destination_key = relative_key

    return destination_key


def copy_object(source_bucket, source_key, dest_bucket, dest_key):
    """Copy an object from source to destination bucket with bucket-owner-full-control."""
    copy_source = {
        'Bucket': source_bucket,
        'Key': source_key
    }

    try:
        s3.copy_object(
            CopySource=copy_source,
            Bucket=dest_bucket,
            Key=dest_key,
            ACL='bucket-owner-full-control'
        )
        logger.info(f"Successfully copied {source_key} to {dest_bucket}/{dest_key}")
    except ClientError as e:
        logger.error(f"Failed to copy object: {e}")
        raise


# =============================================================================
# Manifest-Based Data File Copying
# =============================================================================

def copy_manifest_data_files(source_bucket, manifest_source_key, prefix_config):
    """Read a CUR manifest and copy all referenced data files to the destination.

    This handles SNS-based forwarding where only manifest notifications are sent.
    The manifest's reportKeys list all CSV data files in the assembly. For
    S3-event-based forwarding, files typically already exist and are skipped.

    Returns list of destination keys for successfully copied/verified files.
    """
    try:
        response = s3.get_object(Bucket=source_bucket, Key=manifest_source_key)
        manifest = json.loads(response['Body'].read().decode('utf-8'))
    except Exception as e:
        logger.error(f"Failed to read manifest s3://{source_bucket}/{manifest_source_key}: {e}")
        return []

    report_keys = manifest.get('reportKeys', [])
    if not report_keys:
        logger.info("No reportKeys found in manifest")
        return []

    logger.info(f"Manifest references {len(report_keys)} data file(s), copying to destination")

    copied = []
    for report_key in report_keys:
        dest_key = calculate_destination_key(report_key, prefix_config)

        # Skip if already exists in destination (avoids redundant copies for
        # S3-event-based accounts where data files are copied individually)
        try:
            s3.head_object(Bucket=DESTINATION_BUCKET, Key=dest_key)
            logger.info(f"Data file already exists, skipping: {dest_key}")
            copied.append(dest_key)
            continue
        except ClientError as e:
            if e.response['Error']['Code'] not in ('404', 'NoSuchKey'):
                logger.warning(f"head_object error for {dest_key}: {e}")

        logger.info(f"Copying data file: s3://{source_bucket}/{report_key} -> s3://{DESTINATION_BUCKET}/{dest_key}")
        try:
            copy_object(source_bucket, report_key, DESTINATION_BUCKET, dest_key)
            copied.append(dest_key)
        except Exception as e:
            logger.error(f"Failed to copy data file {report_key}: {e}")

    logger.info(f"Copied/verified {len(copied)}/{len(report_keys)} data file(s) from manifest")
    return copied


# =============================================================================
# Athena Partition Management
# =============================================================================

def is_assembly_manifest(key):
    """Check if this is a CUR Manifest.json inside a timestamped assembly folder.

    Matches: .../YYYYMMDD-YYYYMMDD/YYYYMMDDTHHMMSSz/...-Manifest.json
    Does NOT match top-level manifest: .../YYYYMMDD-YYYYMMDD/...-Manifest.json
    """
    if not key.endswith('Manifest.json'):
        return False
    parts = key.split('/')
    if len(parts) < 3:
        return False
    # Parent folder should be a timestamped assembly ID
    return bool(re.match(r'^\d{8}T\d{6}Z$', parts[-2]))


def is_assembly_data_file(key):
    """Check if this is a CSV data file inside a timestamped assembly folder."""
    if not key.endswith('.csv.gz'):
        return False
    parts = key.split('/')
    if len(parts) < 3:
        return False
    return bool(re.match(r'^\d{8}T\d{6}Z$', parts[-2]))


def find_assembly_manifest(bucket, data_file_key):
    """Find the Manifest.json in the same assembly folder as a data file.

    Returns the manifest key if found, None otherwise.
    """
    assembly_prefix = data_file_key.rsplit('/', 1)[0] + '/'
    response = s3.list_objects_v2(Bucket=bucket, Prefix=assembly_prefix, MaxKeys=50)
    for obj in response.get('Contents', []):
        if obj['Key'].endswith('Manifest.json'):
            return obj['Key']
    return None


def update_athena_partition(bucket, manifest_key):
    """Read manifest and update the Athena partition for this billing period.

    Only updates the partition if data files (.csv.gz) exist in the assembly
    folder. This prevents a race condition where the manifest is copied before
    the data files, which would point the partition to an empty folder.
    """
    logger.info(f"Manifest detected, checking assembly: {manifest_key}")

    # Determine which Athena table to update
    table_name = resolve_table_name(manifest_key)
    if not table_name:
        logger.info(f"No table mapping for key: {manifest_key}, skipping partition update")
        return

    # Parse billing period and assembly ID from the key path
    parts = manifest_key.split('/')
    billing_period = None
    assembly_index = None
    for i, part in enumerate(parts):
        if re.match(r'^\d{8}-\d{8}$', part):
            billing_period = part
            assembly_index = i + 1
            break

    if not billing_period or assembly_index is None or assembly_index >= len(parts):
        logger.warning(f"Could not parse billing period from key: {manifest_key}")
        return

    # Build S3 location for this partition (the timestamped assembly folder)
    partition_path = '/'.join(parts[:assembly_index + 1])
    partition_location = f"s3://{bucket}/{partition_path}/"

    # Verify data files exist in the assembly folder before updating partition.
    # This prevents pointing the partition to a folder that only has the manifest.
    assembly_prefix = partition_path + '/'
    response = s3.list_objects_v2(Bucket=bucket, Prefix=assembly_prefix, MaxKeys=20)
    data_files = [
        obj['Key'] for obj in response.get('Contents', [])
        if obj['Key'].endswith('.csv.gz')
    ]
    if not data_files:
        logger.info(
            f"No data files in assembly folder {assembly_prefix}, "
            f"skipping partition update (data may still be syncing)"
        )
        return

    logger.info(
        f"Updating table '{table_name}' partition "
        f"billing_period='{billing_period}' -> {partition_location} "
        f"({len(data_files)} data files found)"
    )

    glue = get_glue_client()

    # Get storage descriptor from the table definition
    table_response = glue.get_table(DatabaseName=GLUE_DATABASE, Name=table_name)
    sd = table_response['Table']['StorageDescriptor'].copy()
    sd['Location'] = partition_location

    partition_input = {
        'Values': [billing_period],
        'StorageDescriptor': sd,
    }

    # Try update first, create if not found
    try:
        glue.update_partition(
            DatabaseName=GLUE_DATABASE,
            TableName=table_name,
            PartitionValueList=[billing_period],
            PartitionInput=partition_input,
        )
        logger.info(f"Updated partition billing_period={billing_period}")
    except ClientError as e:
        if e.response['Error']['Code'] == 'EntityNotFoundException':
            glue.create_partition(
                DatabaseName=GLUE_DATABASE,
                TableName=table_name,
                PartitionInput=partition_input,
            )
            logger.info(f"Created partition billing_period={billing_period}")
        else:
            raise


def resolve_table_name(key):
    """Resolve which Athena table a key belongs to using TABLE_MAPPING.

    TABLE_MAPPING maps destination_prefix -> table_name, e.g.:
    {"account-prod/": "account_prod", "account-dev/": "account_dev"}
    """
    for prefix, table_name in TABLE_MAPPING.items():
        if key.startswith(prefix):
            return table_name
    return None
