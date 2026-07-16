# =============================================================================
# CUR 2.0 Target Module - Variables
# =============================================================================
# The target module owns the central S3 bucket that receives CUR 2.0 (BCM Data
# Exports) reports written directly cross-account by the source accounts.
# =============================================================================

# -----------------------------------------------------------------------------
# S3 Bucket
# -----------------------------------------------------------------------------

variable "bucket_name" {
  description = "Name of the central S3 bucket that stores CUR 2.0 reports from all source accounts."
  type        = string
  default     = "clb-cur2"
}

# -----------------------------------------------------------------------------
# Source Accounts
# -----------------------------------------------------------------------------

variable "source_account_ids" {
  description = <<-EOT
    AWS account IDs allowed to write CUR 2.0 exports into the bucket.
    Each source account runs the source module, which creates a BCM Data Exports
    export writing directly to this bucket under the `<account_id>/` prefix.
    The account that owns this bucket is always authorized and does not need to
    be listed here.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.source_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "Every source account ID must be a 12-digit AWS account ID."
  }
}

variable "export_region" {
  description = <<-EOT
    Region used to build the aws:SourceArn condition ARNs for the bucket policy.
    BCM Data Exports and legacy CUR definitions live in us-east-1, so this should
    almost always stay at the default.
  EOT
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Lifecycle (CID/CUDOS-inspired)
# -----------------------------------------------------------------------------
# CUR reports are the source of truth and are NEVER expired. We only clean up
# non-current versions left behind by OVERWRITE_REPORT exports and abort stale
# multipart uploads. Transitions to cheaper storage are opt-in.

variable "noncurrent_version_expiration_days" {
  description = "Delete non-current object versions after this many days (CUR exports overwrite in place, leaving old versions behind)."
  type        = number
  default     = 7
}

variable "noncurrent_versions_to_keep" {
  description = "Always retain this many newer non-current versions regardless of age (CID/CUDOS keeps 1)."
  type        = number
  default     = 1
}

variable "abort_multipart_days" {
  description = "Abort incomplete multipart uploads after this many days."
  type        = number
  default     = 7
}

variable "enable_lifecycle_transitions" {
  description = "Transition current CUR objects to cheaper storage classes. Reports are never deleted, only transitioned."
  type        = bool
  default     = false
}

variable "lifecycle_transitions" {
  description = "Storage-class transition schedule for current CUR objects. Only used when enable_lifecycle_transitions = true."
  type = object({
    transition_ia_days      = optional(number, 90)
    transition_glacier_days = optional(number, 180)
  })
  default = {}
}

# -----------------------------------------------------------------------------
# Glue Catalog & Crawler
# -----------------------------------------------------------------------------
# Athena reads the reports through this Glue table. The workgroup and query
# results bucket are NOT created here -- the legacy `cur-analysis` workgroup is
# reused, since it already carries the Grafana reader's permissions.

variable "glue_database_name" {
  description = "Name of the Glue catalog database holding the CUR 2.0 table."
  type        = string
  default     = "cur2_database"
}

variable "glue_table_name" {
  description = "Name of the Glue table covering every source account's CUR 2.0 export."
  type        = string
  default     = "cur2"
}

variable "account_map" {
  description = <<-EOT
    Reference table joining AWS accounts to the client they belong to, so cost can
    be reported per client rather than per account or per organization. Written to
    S3 as CSV and exposed as the Glue table `account_map`.

    This is the authoritative list of accounts. CUR only contains accounts that
    incurred cost, so a zero-spend account appears here but not in `cur2` --
    join `account_map LEFT JOIN cur2`, never the reverse.

    NOTE: `account_name` and `payer_account_id` duplicate data CUR 2.0 already
    carries natively (`line_item_usage_account_name`, `bill_payer_account_id`).
    Keeping them is a deliberate choice for schema parity with the proposal; be
    aware the two copies can drift when an account is renamed in AWS.

    Leave empty to skip creating the table.
  EOT
  type = list(object({
    account_id       = string
    account_name     = string
    client_id        = string
    client_name      = string
    payer_account_id = string
    is_org_member    = bool
    environment      = string
    active           = bool
  }))
  default = []

  validation {
    condition     = alltrue([for a in var.account_map : can(regex("^[0-9]{12}$", a.account_id))])
    error_message = "Every account_id must be a 12-digit AWS account ID."
  }

  validation {
    condition     = length(distinct([for a in var.account_map : a.account_id])) == length(var.account_map)
    error_message = "account_map must not contain duplicate account_id entries."
  }

  # The table is CSV read by LazySimpleSerDe, which has no quoting or escaping
  # whatsoever. A comma inside a value would shift every later column by one and
  # Athena would silently attribute that account's cost to the wrong client --
  # no error, just wrong numbers. Newlines would split the row outright.
  validation {
    condition = alltrue(flatten([
      for a in var.account_map : [
        for field in [a.account_name, a.client_id, a.client_name, a.environment] :
        !can(regex("[,\r\n]", field))
      ]
    ]))
    error_message = "account_map string fields must not contain commas or newlines: the CSV SerDe cannot escape them. Rename the value, e.g. \"Cloud Steroids s.r.o.\" instead of \"Cloud Steroids, s.r.o.\"."
  }
}

variable "account_map_prefix" {
  description = "S3 key prefix for the account_map CSV. Must stay outside the `cur2/` prefix so the crawler ignores it."
  type        = string
  default     = "reference/account_map"
}

variable "crawler_name" {
  description = "Name of the Glue crawler that discovers CUR 2.0 partitions."
  type        = string
  default     = "cur2-crawler"
}

variable "crawler_role_name" {
  description = "Name of the IAM role assumed by the CUR 2.0 Glue crawler."
  type        = string
  default     = "cur2-crawler-role"
}

variable "crawler_schedule" {
  description = <<-EOT
    Cron schedule for the Glue crawler, in Glue's `cron(...)` syntax (UTC).
    Defaults to 02:00 UTC daily, matching CID. Set to null to disable the
    schedule and run the crawler on demand only.
  EOT
  type        = string
  default     = "cron(0 2 * * ? *)"
}

# -----------------------------------------------------------------------------
# Athena (optional)
# -----------------------------------------------------------------------------
# A fresh consumer needs somewhere to run queries. Set enable_athena = false to
# reuse an existing workgroup (e.g. the SRE setup shares the legacy one).

variable "enable_athena" {
  description = "Create an Athena workgroup and its query-results bucket for querying the CUR 2.0 data."
  type        = bool
  default     = true
}

variable "athena_workgroup_name" {
  description = "Name of the Athena workgroup (only when enable_athena = true)."
  type        = string
  default     = "cur2-analysis"
}

variable "athena_results_bucket_name" {
  description = "Name for the Athena query-results bucket. Defaults to `<bucket_name>-athena-results`."
  type        = string
  default     = ""
}

variable "athena_query_results_retention_days" {
  description = "Days to retain Athena query results (temporary query outputs, not CUR data)."
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Reader access (optional)
# -----------------------------------------------------------------------------
# Read-only identities for querying the data (e.g. Grafana, ClickHouse). Set
# both to false to manage read access yourself against the module outputs.

variable "create_reader_role" {
  description = "Create a read-only IAM role (assumed from within the account) with S3 + Glue + Athena read access."
  type        = bool
  default     = true
}

variable "require_mfa_for_reader_role" {
  description = "Require MFA when assuming the reader role."
  type        = bool
  default     = true
}

variable "create_reader_user" {
  description = "Create a read-only IAM user with static access keys (for tools that cannot assume a role)."
  type        = bool
  default     = false
}

variable "reader_name_prefix" {
  description = "Prefix for reader IAM resource names (role `<prefix>-reader-role`, user `svc-<prefix>-reader`)."
  type        = string
  default     = "cur2"
}

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to created resources."
  type        = map(string)
  default     = {}
}
