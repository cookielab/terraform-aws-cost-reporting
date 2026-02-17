# Terraform module for AWS Cost Reporting

Multi-account AWS Cost and Usage Report (CUR) aggregation and analysis. This module provides two submodules:

- **`modules/source`** - Deployed in each source AWS account. Creates CUR report definition, S3 bucket, and event notification to forward reports to the target account.
- **`modules/target`** - Deployed in the central/target AWS account. Aggregates CUR reports from multiple source accounts using a Lambda function, with optional Athena/Glue analysis and IAM access management.

## Architecture

```
┌─────────────────────┐     ┌─────────────────────┐
│  Source Account A    │     │  Source Account B    │
│                     │     │                     │
│  CUR Report → S3    │     │  CUR Report → S3    │
│       │             │     │       │             │
│       └─── S3 Event ─┼─────┼───── S3 Event ─────┤
└─────────────────────┘     └─────────────────────┘
                    │                   │
                    ▼                   ▼
          ┌─────────────────────────────────┐
          │       Target Account            │
          │                                 │
          │  Lambda (CUR Forwarder)         │
          │       │                         │
          │       ▼                         │
          │  S3 Bucket (Aggregated CUR)     │
          │       │                         │
          │       ▼ (optional)              │
          │  Athena + Glue (Analysis)       │
          │  IAM Roles/Users (Access)       │
          └─────────────────────────────────┘
```

## Usage

### 1. Deploy the target module first (central account)

```terraform
module "cur_target" {
  source = "cookielab/cost-reporting/aws//modules/target"

  cur_reports_bucket_name = "my-aggregated-cur-reports"

  source_accounts = {
    "prod" = {
      account_id = "111111111111"
    }
    "staging" = {
      account_id = "222222222222"
    }
  }

  enable_athena = true
}
```

### 2. Deploy the source module in each source account

```terraform
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "cur_source" {
  source = "cookielab/cost-reporting/aws//modules/source"

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  lambda_function_arn     = "arn:aws:lambda:eu-west-1:000000000000:function:cur-forwarder"
  lambda_function_role_arn = "arn:aws:iam::000000000000:role/cur-forwarder-role"
}
```

## Source Module

Creates AWS CUR report definition and S3 bucket in a source account, with cross-account access for the target Lambda.

### Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5, < 2.0 |
| aws | >= 5.27 |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| lambda_function_arn | ARN of the Lambda function in the target account | `string` | n/a | yes |
| lambda_function_role_arn | ARN of the IAM role for the Lambda function (for bucket policy) | `string` | n/a | yes |
| s3_bucket_name | S3 bucket name (defaults to `cur-csv-{account_id}`) | `string` | `null` | no |
| cur_time_unit | Time unit for CUR report (`HOURLY` or `DAILY`) | `string` | `"HOURLY"` | no |
| cur_format | Report format (`textORcsv` or `Parquet`) | `string` | `"textORcsv"` | no |
| cur_compression | Compression (`GZIP`, `ZIP`, or `Parquet`) | `string` | `"GZIP"` | no |
| s3_bucket_lifecycle | S3 lifecycle transitions | `object` | `{transition_to_ia_days=90, transition_to_glacier_days=180}` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
|------|-------------|
| bucket_id | ID of the CUR S3 bucket |
| bucket_arn | ARN of the CUR S3 bucket |
| bucket_name | Name of the CUR S3 bucket |
| cur_report_name | Name of the CUR report |
| cur_prefix | S3 prefix where CUR reports are stored |
| account_id | AWS Account ID |

## Target Module

Aggregates CUR reports from multiple source accounts into a central S3 bucket using Lambda, with optional Athena analysis.

### Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5, < 2.0 |
| aws | >= 5.27 |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cur_reports_bucket_name | Name of the S3 bucket for aggregated CUR reports | `string` | n/a | yes |
| source_accounts | Map of source account configurations | `map(object)` | `{}` | no |
| create_bucket | Whether to create a new S3 bucket | `bool` | `true` | no |
| enable_athena | Enable Athena/Glue for CUR analysis | `bool` | `true` | no |
| create_reader_role | Create IAM role for read-only access | `bool` | `true` | no |
| create_reader_user | Create IAM user with access keys | `bool` | `false` | no |
| lambda_function_name | Name of the Lambda function | `string` | `"cur-forwarder"` | no |
| glue_database_name | Glue database name for partition management | `string` | `""` | no |
| glue_region | AWS region for Glue catalog | `string` | `"eu-west-1"` | no |
| table_mapping | Map of destination_prefix to Glue table name | `map(string)` | `{}` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
|------|-------------|
| bucket_id | ID of the aggregated CUR S3 bucket |
| bucket_arn | ARN of the aggregated CUR S3 bucket |
| lambda_function_arn | ARN of the Lambda function |
| lambda_function_name | Name of the Lambda function |
| lambda_role_arn | ARN of the Lambda IAM role |
| athena_workgroup_name | Athena workgroup name |
| glue_database_name | Glue database name |
| reader_role_arn | IAM role ARN for read-only access |

## Bootstrap Script

For existing CUR data, use `modules/target/scripts/bootstrap_partitions.py` to create initial Glue partitions. Configure the variables at the top of the script and run:

```bash
export AWS_PROFILE=your-profile
python3 modules/target/scripts/bootstrap_partitions.py
```
