# =============================================================================
# Target Module Variables (CUR 2.0 Data Exports aggregation)
# =============================================================================

# -----------------------------------------------------------------------------
# S3 Bucket Configuration
# -----------------------------------------------------------------------------

variable "create_bucket" {
  description = "Whether to create the central CUR bucket or use an existing one"
  type        = bool
  default     = true
}

variable "cur_reports_bucket_name" {
  description = "Name of the central S3 bucket for CUR 2.0 Data Exports (created if create_bucket=true, otherwise name of the existing bucket)"
  type        = string
}

variable "source_account_ids" {
  description = "AWS account IDs allowed to deliver CUR 2.0 Data Exports into the bucket (used in the bucket policy). Only needed when create_bucket=true."
  type        = list(string)
  default     = []
}

variable "enable_lifecycle_transitions" {
  description = "Enable lifecycle transitions to cheaper storage classes for CUR reports (reports are never deleted)"
  type        = bool
  default     = false
}

variable "cur_reports_bucket_lifecycle" {
  description = "Lifecycle transition configuration for the CUR bucket. Only used when enable_lifecycle_transitions = true."
  type = object({
    transition_ia_days      = optional(number, 30)
    transition_glacier_days = optional(number, 90)
  })
  default = {
    transition_ia_days      = 30
    transition_glacier_days = 90
  }
}

# -----------------------------------------------------------------------------
# Athena / Glue Configuration
# -----------------------------------------------------------------------------

variable "enable_athena" {
  description = "Enable the Athena workgroup and Glue catalog (database + crawler) for CUR 2.0 analysis"
  type        = bool
  default     = true
}

variable "glue_database_name" {
  description = "Name of the Glue database for CUR 2.0 data"
  type        = string
  default     = "cur2_database"
}

variable "data_export_prefix" {
  description = "S3 prefix under the CUR bucket where Data Exports are delivered (the crawler scans this path)"
  type        = string
  default     = "cur2/"
}

variable "crawler_schedule" {
  description = "Cron expression for the Glue crawler schedule (discovers partitions and reconciles schema)"
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "account_map" {
  description = <<-EOT
    Optional account ID to name/client mapping, uploaded as a CSV and exposed as
    the `account_map` Glue table for joins. Empty = do not manage the account map.
    In practice you only fill account_id and account_name; the rest have defaults.
  EOT
  type = list(object({
    account_id       = string
    account_name     = string
    client_id        = optional(string, "")
    client_name      = optional(string, "")
    payer_account_id = optional(string)
    is_org_member    = optional(bool, true)
    environment      = optional(string, "production")
    active           = optional(bool, true)
  }))
  default = []
}

variable "athena_results_bucket_name_override" {
  description = "Override name for the Athena results bucket (defaults to {cur_reports_bucket_name}-athena-results)"
  type        = string
  default     = ""
}

variable "athena_query_results_retention_days" {
  description = "Days to retain Athena query results (temporary query outputs, not CUR data)"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------
# Access Identities Configuration
# -----------------------------------------------------------------------------

variable "create_reader_role" {
  description = "Create IAM role for read-only CUR access (for AssumeRole)"
  type        = bool
  default     = true
}

variable "require_mfa_for_reader_role" {
  description = "Require MFA for assuming the CUR reader role (security best practice)"
  type        = bool
  default     = true
}

variable "create_reader_user" {
  description = "Create IAM user with access keys for read-only access (e.g., for Grafana, ClickHouse)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
