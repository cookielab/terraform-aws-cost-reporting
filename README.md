# Terraform module for AWS Cost Reporting (CUR 2.0)

Multi-account AWS cost aggregation and analysis built on **CUR 2.0 / BCM Data
Exports**. Each source account delivers a Parquet export straight into a central
bucket cross-account; the central account catalogues it with a Glue crawler and
exposes it through Athena. There is no forwarding Lambda and no CSV.

- **`modules/source`** – Deployed in each source account. Creates one BCM Data
  Exports export (CUR 2.0) that writes Parquet directly into the central bucket.
- **`modules/target`** – Deployed in the central account. Owns the aggregation
  bucket, the Glue database + pre-created `cur2` table + crawler that discovers
  partitions and reconciles the schema, and an optional `account_map` reference
  table.

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

  bucket_name = "clb-cur2"

  # Accounts allowed to deliver Data Exports into the bucket (bucket policy).
  # The bucket-owning account is authorized automatically.
  source_account_ids = ["111111111111", "222222222222"]

  # Optional reference table joining accounts to clients (for per-client cost).
  account_map = [
    { account_id = "111111111111", account_name = "Prod", client_id = "acme", client_name = "Acme", payer_account_id = "111111111111", is_org_member = true, environment = "production", active = true },
  ]
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

Owns the central bucket and the Glue catalog. Terraform pre-creates the `cur2`
table with named partition keys and the CID column set; the Glue crawler then
adds partitions and reconciles new columns on a schedule. Also manages an
optional `account_map` reference table. Does not create an Athena workgroup or
reader IAM — those are wired up separately.

### Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.5, < 2.0 |
| aws | >= 6.0 |

### Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| bucket_name | Name of the central CUR 2.0 bucket | `string` | `"clb-cur2"` | no |
| source_account_ids | Account IDs allowed to deliver Data Exports (bucket-owner is added automatically) | `list(string)` | `[]` | no |
| export_region | Region used to build the `aws:SourceArn` condition ARNs | `string` | `"us-east-1"` | no |
| noncurrent_version_expiration_days | Delete non-current object versions after N days | `number` | `7` | no |
| noncurrent_versions_to_keep | Newer non-current versions always retained | `number` | `1` | no |
| abort_multipart_days | Abort incomplete multipart uploads after N days | `number` | `7` | no |
| enable_lifecycle_transitions | Transition current CUR objects to cheaper storage (never deletes) | `bool` | `false` | no |
| lifecycle_transitions | Storage-class transition schedule (when transitions enabled) | `object` | `{ia=90, glacier=180}` | no |
| glue_database_name | Glue database name | `string` | `"cur2_database"` | no |
| glue_table_name | Glue table name | `string` | `"cur2"` | no |
| account_map | Optional account→client mapping (CSV + Glue table); all fields required | `list(object)` | `[]` | no |
| account_map_prefix | S3 key prefix for the account_map CSV (outside `cur2/`) | `string` | `"reference/account_map"` | no |
| crawler_name | Name of the Glue crawler | `string` | `"cur2-crawler"` | no |
| crawler_role_name | Name of the crawler IAM role | `string` | `"cur2-crawler-role"` | no |
| crawler_schedule | Crawler cron schedule (null to disable) | `string` | `"cron(0 2 * * ? *)"` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

### Outputs

| Name | Description |
|------|-------------|
| bucket_id | Name/ID of the central CUR 2.0 bucket |
| bucket_arn | ARN of the central CUR 2.0 bucket |
| authorized_account_ids | Account IDs authorized to write into the bucket |
| glue_database_name | Glue catalog database name |
| glue_database_arn | Glue catalog database ARN |
| glue_table_name | Glue table covering every account's export |
| account_map_table_name | account_map Glue table name (null when unset) |
| crawler_name | Name of the Glue crawler |

## Notes

- The `cur2` Glue table is **pre-created by Terraform** with named partition keys
  (`source_account_id`, `report_name`, `data`, `billing_period`) and the CID
  column set. The crawler then only adds partitions and reconciles new columns
  (`MergeNewColumns`) — Terraform ignores those changes via `lifecycle`.
  Letting the crawler create the table would name the first three partition
  levels `partition_0..2`, which is why it is declared here instead.
- The module does **not** create an Athena workgroup or reader IAM — wire those
  up separately (the SRE setup reuses the existing `cur-analysis` workgroup).
- `account_map` values must not contain commas or newlines (LazySimpleSerDe
  cannot escape them); a validation enforces this.
