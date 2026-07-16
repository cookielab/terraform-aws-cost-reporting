# =============================================================================
# Local Values
# =============================================================================

locals {
  # Bucket references:
  # - create_bucket=true  -> use module outputs
  # - create_bucket=false -> construct from bucket name
  #
  # NOTE: we construct ARNs directly instead of using a data source so cross-region
  # setups (bucket created by another module in the same apply) don't fail during plan.
  cur_bucket_id  = var.create_bucket ? module.cur_bucket[0].s3_bucket_id : var.cur_reports_bucket_name
  cur_bucket_arn = var.create_bucket ? module.cur_bucket[0].s3_bucket_arn : "arn:aws:s3:::${var.cur_reports_bucket_name}"

  athena_results_bucket_name = var.athena_results_bucket_name_override != "" ? var.athena_results_bucket_name_override : "${var.cur_reports_bucket_name}-athena-results"
}

# =============================================================================
# Athena / Glue Submodule (crawler owns the cur2 table)
# =============================================================================

module "athena" {
  source = "./athena"
  count  = var.enable_athena ? 1 : 0

  cur_bucket_id  = local.cur_bucket_id
  cur_bucket_arn = local.cur_bucket_arn

  glue_database_name = var.glue_database_name
  data_export_prefix = var.data_export_prefix
  crawler_schedule   = var.crawler_schedule
  account_map        = var.account_map

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

  enable_athena_access      = var.enable_athena
  glue_database_name        = var.enable_athena ? module.athena[0].glue_database_name : ""
  athena_workgroup_name     = var.enable_athena ? module.athena[0].workgroup_name : ""
  athena_results_bucket_arn = var.enable_athena ? module.athena[0].athena_results_bucket_arn : ""

  tags = var.tags
}
