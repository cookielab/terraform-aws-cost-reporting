# Terraform module for AWS Cost Reporting (CUR 2.0)

Multi-account AWS cost aggregation and analysis built on **CUR 2.0 / BCM Data
Exports**. Each source account delivers a Parquet export straight into a central
bucket cross-account; the central account catalogues it with a Glue crawler and
exposes it through Athena. There is no forwarding Lambda and no CSV.

- **`modules/source`** – Deployed in each source account. Creates one BCM Data
  Exports export (CUR 2.0) that writes Parquet directly into the central bucket.
- **`modules/target`** – Deployed in the central account. Owns the aggregation
  bucket, a Glue database + crawler that discovers partitions and reconciles the
  schema, an Athena workgroup, an optional `account_map` reference table, and
  optional read-only IAM access.

## Architecture

```
┌─────────────────────┐   ┌─────────────────────┐
│  Source Account A   │   │  Source Account B   │
│  BCM Data Export    │   │  BCM Data Export    │
│  (CUR 2.0, Parquet) │   │  (CUR 2.0, Parquet) │
└──────────┬──────────┘   └──────────┬──────────┘
           │  cross-account S3 PutObject (bcm-data-exports.amazonaws.com)
           ▼                          ▼
        ┌────────────────────────────────────────┐
        │            Target Account              │
        │                                        │
        │  S3  cur2/<account_id>/cur2/data/      │
        │           BILLING_PERIOD=YYYY-MM/*.parquet
        │   │                                    │
        │   ▼                                    │
        │  Glue crawler → cur2_database.cur2     │
        │   │            (+ account_map table)   │
        │   ▼                                    │
        │  Athena workgroup + read-only IAM      │
        └────────────────────────────────────────┘
```

Delivered layout (every segment below the table location is a partition key):

```
<bucket>/cur2/<account_id>/cur2/data/BILLING_PERIOD=YYYY-MM/cur2-00001.snappy.parquet
<bucket>/cur2/<account_id>/cur2/metadata/BILLING_PERIOD=YYYY-MM/cur2-Manifest.json
```

## Usage

### 1. Target module first (central account)

```terraform
module "cur_target" {
  source = "cookielab/cost-reporting/aws//modules/target"

  cur_reports_bucket_name = "clb-cur2"

  # Accounts allowed to deliver Data Exports into the bucket (bucket policy).
  source_account_ids = ["111111111111", "222222222222"]

  # Optional reference table for readable account/client names in queries.
  account_map = [
    { account_id = "111111111111", account_name = "Prod" },
    { account_id = "222222222222", account_name = "Staging" },
  ]

  enable_athena = true
}
```

### 2. Source module in each source account

BCM Data Exports is a **us-east-1** service, so the module requires an
`aws.us_east_1` provider alias regardless of where the bucket lives.

```terraform
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

module "cur_source" {
  source = "cookielab/cost-reporting/aws//modules/source"

  providers = { aws.us_east_1 = aws.us_east_1 }

  destination_bucket       = "clb-cur2"
  destination_region       = "eu-west-1"
  destination_bucket_owner = "000000000000" # central account that owns the bucket
}
```

## Source Module

Creates a single CUR 2.0 export via the Cloud Control API (needed to set
`S3BucketOwner` for cross-account delivery). Defaults mirror the CID
data-exports template so CID SQL/dashboards work against the resulting table.

### Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5, < 2.0 |
| aws (`aws.us_east_1`) | >= 5.40 |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| destination_bucket | Central bucket the export writes into | `string` | n/a | yes |
| destination_region | Region the destination bucket lives in | `string` | n/a | yes |
| destination_bucket_owner | Account ID owning the bucket (cross-account delivery) | `string` | `null` | no |
| s3_prefix | Prefix before the export name (defaults to `cur2/<account_id>`) | `string` | `null` | no |
| export_name | Export name; becomes the `report_name` partition | `string` | `"cur2"` | no |
| description | Export description | `string` | `"CUR 2.0 export aggregated..."` | no |
| time_granularity | `HOURLY`, `DAILY`, or `MONTHLY` | `string` | `"HOURLY"` | no |
| enable_split_cost_allocation_data | Add `split_line_item_*` columns | `bool` | `true` | no |
| enable_iam_principal_data | Add `line_item_iam_principal` column | `bool` | `true` | no |
| billing_view_arn | Billing view to source from (primary if unset) | `string` | `null` | no |
| overwrite | `OVERWRITE_REPORT` or `CREATE_NEW_REPORT` | `string` | `"OVERWRITE_REPORT"` | no |
| tags | Tags (no parentheses in values) | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
|------|-------------|
| export_arn | ARN of the CUR 2.0 export |
| export_name | Export name (also the `report_name` partition) |
| account_id | Account the export was created in (`source_account_id` partition) |
| s3_prefix | Prefix under the destination bucket |
| s3_destination | Root S3 path reports are written under |
| query_columns | Columns selected after applying INCLUDE_* toggles |

## Target Module

Owns the central bucket and catalogues the delivered exports with a Glue
crawler. The crawler creates and maintains the `cur2` table (schema + all
partitions) on a schedule — Terraform does not define the table columns.

### Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5, < 2.0 |
| aws | >= 5.27 |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| cur_reports_bucket_name | Name of the central CUR 2.0 bucket | `string` | n/a | yes |
| create_bucket | Create the bucket or use an existing one | `bool` | `true` | no |
| source_account_ids | Account IDs allowed to deliver Data Exports (bucket policy) | `list(string)` | `[]` | no |
| enable_lifecycle_transitions | Transition older data to cheaper storage (never deletes) | `bool` | `false` | no |
| cur_reports_bucket_lifecycle | Transition-day configuration | `object` | `{ia=30, glacier=90}` | no |
| enable_athena | Create Athena workgroup + Glue database/crawler | `bool` | `true` | no |
| glue_database_name | Glue database name | `string` | `"cur2_database"` | no |
| data_export_prefix | Prefix the crawler scans | `string` | `"cur2/"` | no |
| crawler_schedule | Crawler cron schedule | `string` | `"cron(0 2 * * ? *)"` | no |
| account_map | Optional account→name/client mapping (CSV + Glue table) | `list(object)` | `[]` | no |
| athena_results_bucket_name_override | Override for the Athena results bucket name | `string` | `""` | no |
| athena_query_results_retention_days | Retention for temporary query outputs | `number` | `30` | no |
| create_reader_role | Create read-only IAM role (AssumeRole) | `bool` | `true` | no |
| require_mfa_for_reader_role | Require MFA to assume the reader role | `bool` | `true` | no |
| create_reader_user | Create read-only IAM user with access keys | `bool` | `false` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
|------|-------------|
| bucket_id | ID of the aggregated CUR 2.0 bucket |
| bucket_arn | ARN of the aggregated CUR 2.0 bucket |
| athena_workgroup_name | Athena workgroup name |
| glue_database_name | Glue database name |
| glue_crawler_name | Name of the crawler that owns the `cur2` table |
| reader_role_arn | IAM role ARN for read-only access |
| reader_access_key_id | Access key ID for the reader user (sensitive) |
| reader_secret_access_key | Secret access key for the reader user (sensitive) |

## Notes

- The Glue crawler owns the `cur2` table. Right after the first `terraform
  apply` the table does not exist yet — it appears after the crawler's first run
  (trigger it manually once, or wait for the schedule).
- `account_map` only requires `account_id` and `account_name` per entry; the
  remaining columns (`client_id`, `environment`, …) have sensible defaults.
