# =============================================================================
# CUR 2.0 Source Module - Variables
# =============================================================================
# Creates a CUR 2.0 (BCM Data Exports) export that writes Parquet reports
# directly, cross-account, into the central bucket owned by the target module.
# Defaults mirror the CID data-exports template so CID SQL queries and
# dashboards work against the resulting table unchanged.
# =============================================================================

# -----------------------------------------------------------------------------
# Destination
# -----------------------------------------------------------------------------

variable "destination_bucket" {
  description = "Name of the central bucket the export writes into (the target module's bucket)."
  type        = string
}

variable "destination_region" {
  description = "Region the destination bucket lives in. Not the export's own region - BCM Data Exports always lives in us-east-1."
  type        = string
}

variable "destination_bucket_owner" {
  description = <<-EOT
    AWS account ID that owns the destination bucket. Required for cross-account
    delivery - passed to BCM Data Exports as S3BucketOwner so it can validate
    the bucket in the owner account. Leave null for same-account delivery.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.destination_bucket_owner == null || can(regex("^[0-9]{12}$", var.destination_bucket_owner))
    error_message = "destination_bucket_owner must be a 12-digit AWS account ID or null."
  }
}

variable "s3_prefix" {
  description = <<-EOT
    Prefix under the destination bucket, prepended before the export name.
    Defaults to "cur2/<account_id>" (the CID layout), making the delivered path
    <bucket>/cur2/<account_id>/<export_name>/data/BILLING_PERIOD=YYYY-MM/.
    Every segment below the Glue table location is a partition key, so this is
    load-bearing rather than cosmetic - change with care.
  EOT
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Export definition
# -----------------------------------------------------------------------------

variable "export_name" {
  description = "Name of the export. Becomes a path segment, and therefore the value of the report_name Glue partition."
  type        = string
  default     = "cur2"
}

variable "description" {
  description = "Description of the export."
  type        = string
  default     = "CUR 2.0 export aggregated in the central cost reporting bucket"
}

variable "time_granularity" {
  description = <<-EOT
    Granularity of the report rows. Not a safe in-place change: switching it
    requires recreating the export, purging the delivered data and requesting a
    backfill. HOURLY is recommended.
  EOT
  type        = string
  default     = "HOURLY"

  validation {
    condition     = contains(["HOURLY", "DAILY", "MONTHLY"], var.time_granularity)
    error_message = "time_granularity must be one of HOURLY, DAILY, MONTHLY."
  }
}

variable "enable_split_cost_allocation_data" {
  description = "Include split cost allocation data, adding the split_line_item_* columns. Disable if dataset size causes performance issues."
  type        = bool
  default     = true
}

variable "enable_iam_principal_data" {
  description = "Include IAM principal allocation data, adding the line_item_iam_principal column. Data is available from 2026-04-08 onwards."
  type        = bool
  default     = true
}

variable "billing_view_arn" {
  description = "Billing view ARN to source the data from. Unset by default, matching the CID template, which sources from the account's primary billing view."
  type        = string
  default     = null
}

variable "overwrite" {
  description = <<-EOT
    Delivery mode for each refresh:
    - OVERWRITE_REPORT: replace the report in place (a single current copy).
    - CREATE_NEW_REPORT: keep every refresh as a timestamped snapshot.
    OVERWRITE_REPORT is strongly preferred: snapshots multiply storage and break
    the flat partition layout the Glue table expects.
  EOT
  type        = string
  default     = "OVERWRITE_REPORT"

  validation {
    condition     = contains(["OVERWRITE_REPORT", "CREATE_NEW_REPORT"], var.overwrite)
    error_message = "overwrite must be OVERWRITE_REPORT or CREATE_NEW_REPORT."
  }
}

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to the export. Values may not contain parentheses - AWS rejects them with InvalidTag."
  type        = map(string)
  default     = {}
}
