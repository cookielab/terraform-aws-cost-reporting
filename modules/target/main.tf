data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Local Values
# =============================================================================

locals {
  # Bucket references:
  # - create_bucket=true -> use module outputs
  # - create_bucket=false -> construct from bucket name
  #
  # NOTE: We don't use data source here because in cross-region setups, the bucket
  # might be created by another module in the same apply, causing "empty result" errors
  # during plan phase. S3 ARNs are deterministic so we can construct them directly.
  cur_bucket_id  = var.create_bucket ? module.cur_bucket[0].s3_bucket_id : var.cur_reports_bucket_name
  cur_bucket_arn = var.create_bucket ? module.cur_bucket[0].s3_bucket_arn : "arn:aws:s3:::${var.cur_reports_bucket_name}"

  # Expand source_accounts with defaults
  source_accounts_full = {
    for source_account_name, config in var.source_accounts : source_account_name => {
      account_id         = config.account_id
      bucket_name        = config.bucket_name != null ? config.bucket_name : "cur-csv-${config.account_id}"
      bucket_arn         = "arn:aws:s3:::${config.bucket_name != null ? config.bucket_name : "cur-csv-${config.account_id}"}"
      source_prefix      = config.source_prefix != null ? config.source_prefix : "cur-csv/"
      destination_prefix = config.destination_prefix != null ? config.destination_prefix : "${source_account_name}/"
    }
  }

  # Expand athena source accounts (use athena_source_accounts if provided, otherwise source_accounts)
  athena_accounts_full = {
    for source_account_name, config in(length(var.athena_source_accounts) > 0 ? var.athena_source_accounts : var.source_accounts) : source_account_name => {
      account_id         = config.account_id
      bucket_name        = config.bucket_name != null ? config.bucket_name : "cur-csv-${config.account_id}"
      source_prefix      = config.source_prefix != null ? config.source_prefix : "cur-csv/"
      destination_prefix = config.destination_prefix != null ? config.destination_prefix : "${source_account_name}/"
    }
  }

  # Lambda builds bucket
  lambda_builds_bucket = var.lambda_builds_bucket_id != "" ? var.lambda_builds_bucket_id : local.cur_bucket_id
  use_s3_for_lambda    = var.lambda_builds_bucket_id != ""

  # Athena results bucket name
  athena_results_bucket_name = var.athena_results_bucket_name_override != "" ? var.athena_results_bucket_name_override : "${var.cur_reports_bucket_name}-athena-results"
}

# =============================================================================
# Athena/Glue Submodule
# =============================================================================

module "athena" {
  source = "./athena"
  count  = var.enable_athena ? 1 : 0

  cur_bucket_id  = local.cur_bucket_id
  cur_bucket_arn = local.cur_bucket_arn

  source_accounts = {
    for key, value in local.athena_accounts_full : key => {
      account_id         = value.account_id
      destination_prefix = value.destination_prefix
    }
  }

  accounts_with_misaligned_columns    = var.accounts_with_misaligned_columns
  athena_results_bucket_name          = local.athena_results_bucket_name
  athena_query_results_retention_days = var.athena_query_results_retention_days

  tags = var.tags
}

# =============================================================================
# Access Identities Submodule
# =============================================================================

module "access_identities" {
  source = "./access_identities"
  count  = var.create_reader_role || var.create_reader_user ? 1 : 0

  cur_bucket_id  = local.cur_bucket_id
  cur_bucket_arn = local.cur_bucket_arn
  name_prefix    = var.cur_reports_bucket_name

  create_reader_role          = var.create_reader_role
  require_mfa_for_reader_role = var.require_mfa_for_reader_role
  create_reader_user          = var.create_reader_user

  # Include Athena permissions if Athena is enabled
  enable_athena_access      = var.enable_athena
  glue_database_name        = var.enable_athena ? module.athena[0].glue_database_name : ""
  athena_workgroup_name     = var.enable_athena ? module.athena[0].workgroup_name : ""
  athena_results_bucket_arn = var.enable_athena ? module.athena[0].athena_results_bucket_arn : ""

  tags = var.tags
}
