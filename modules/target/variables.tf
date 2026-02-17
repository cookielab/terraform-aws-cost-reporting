# =============================================================================
# Target Module Variables
# =============================================================================

# -----------------------------------------------------------------------------
# S3 Bucket Configuration
# -----------------------------------------------------------------------------

variable "create_bucket" {
  description = "Whether to create a new S3 bucket or use an existing one"
  type        = bool
  default     = true
}

variable "cur_reports_bucket_name" {
  description = "Name of the S3 bucket for CUR reports (created if create_bucket=true, or name of existing bucket if create_bucket=false)"
  type        = string
}

variable "enable_lifecycle_transitions" {
  description = "Enable lifecycle transitions to cheaper storage classes for CUR reports"
  type        = bool
  default     = false
}

variable "cur_reports_bucket_lifecycle" {
  description = <<-EOT
    Lifecycle configuration for CUR reports bucket.
    Only used when enable_lifecycle_transitions = true.
    Reports are NEVER deleted - only transitioned to cheaper storage.
  EOT
  type = object({
    transition_ia_days      = optional(number, 30)
    transition_glacier_days = optional(number, 90)
  })
  default = {
    transition_ia_days      = 30
    transition_glacier_days = 90
  }
}

variable "lambda_builds_bucket_id" {
  description = "ID of bucket for Lambda builds (defaults to CUR bucket if not specified)"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Source Accounts Configuration
# -----------------------------------------------------------------------------

variable "source_accounts" {
  description = <<-EOT
    Map of source account configurations for CUR forwarding.
    Key: unique identifier for the source account (used for naming resources)

    Required fields:
    - account_id: AWS Account ID of the source account

    Optional fields:
    - bucket_name: S3 bucket name in source account (defaults to cur-csv-{account_id})
    - source_prefix: S3 prefix in source bucket (defaults to cur-csv/)
    - destination_prefix: S3 prefix in target bucket (defaults to {key}/)
  EOT
  type = map(object({
    account_id         = string
    bucket_name        = optional(string)
    source_prefix      = optional(string)
    destination_prefix = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Lambda Configuration
# -----------------------------------------------------------------------------

variable "lambda_function_name" {
  description = "Name of the Lambda function for CUR forwarding"
  type        = string
  default     = "cur-forwarder"
}

variable "lambda_artifacts_dir" {
  description = "Directory name where Lambda build artifacts are stored (must be unique per module instance to avoid race conditions)"
  type        = string
  default     = "builds"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

# -----------------------------------------------------------------------------
# Athena/Glue Configuration
# -----------------------------------------------------------------------------

variable "enable_athena" {
  description = "Enable Athena workgroup and Glue catalog for CUR analysis"
  type        = bool
  default     = true
}

variable "athena_results_bucket_name_override" {
  description = "Override name for Athena results bucket (defaults to {cur_reports_bucket_name}-athena-results)"
  type        = string
  default     = ""
}

variable "glue_database_name" {
  description = "Name of the Glue database for partition management (empty = disable partition updates)"
  type        = string
  default     = ""
}

variable "glue_region" {
  description = "AWS region where the Glue catalog lives (for cross-region Lambda calls)"
  type        = string
  default     = "eu-west-1"
}

variable "table_mapping" {
  description = "Map of destination_prefix -> Glue table name for Lambda partition management"
  type        = map(string)
  default     = {}
}

variable "athena_query_results_retention_days" {
  description = "Days to retain Athena query results (temporary query outputs, not CUR data)"
  type        = number
  default     = 30
}

variable "athena_source_accounts" {
  description = <<-EOT
    Map of source accounts for Athena/Glue crawlers only (no Lambda functions).
    Use this when you want to create crawlers for source accounts whose Lambda functions
    are in a different region/module. Same structure as source_accounts.
    If not provided, crawlers will be created from source_accounts.
  EOT
  type = map(object({
    account_id         = string
    bucket_name        = optional(string)
    source_prefix      = optional(string)
    destination_prefix = optional(string)
  }))
  default = {}
}

variable "accounts_with_misaligned_columns" {
  description = <<-EOT
    Set of source account keys that have misaligned columns due to OpenCSVSerDe bug.
    This occurs when the invoicing entity contains a comma (e.g., "Amazon Web Services, Inc.")
    which causes column shifting in CSV parsing. Named queries will be created to fix these.
  EOT
  type        = set(string)
  default     = []
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
