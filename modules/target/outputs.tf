# =============================================================================
# CUR 2.0 Target Module - Outputs
# =============================================================================

output "bucket_id" {
  description = "Name/ID of the central CUR 2.0 bucket."
  value       = module.cur_bucket.s3_bucket_id
}

output "bucket_arn" {
  description = "ARN of the central CUR 2.0 bucket (pass to the source module's s3_bucket_arn)."
  value       = module.cur_bucket.s3_bucket_arn
}

output "authorized_account_ids" {
  description = "Account IDs authorized to write CUR 2.0 exports into the bucket."
  value       = local.authorized_account_ids
}

output "glue_database_name" {
  description = "Glue catalog database holding the CUR 2.0 table (point the Grafana Athena datasource at this)."
  value       = aws_glue_catalog_database.cur2.name
}

output "glue_database_arn" {
  description = "ARN of the Glue catalog database."
  value       = aws_glue_catalog_database.cur2.arn
}

output "glue_table_name" {
  description = "Glue table covering every source account's CUR 2.0 export."
  value       = aws_glue_catalog_table.cur2.name
}

output "account_map_table_name" {
  description = "Glue table mapping accounts to clients, or null when account_map is empty."
  value       = local.create_account_map ? aws_glue_catalog_table.account_map[0].name : null
}

output "crawler_name" {
  description = "Name of the Glue crawler (run on demand with `aws glue start-crawler`)."
  value       = aws_glue_crawler.cur2.name
}

output "athena_workgroup_name" {
  description = "Athena workgroup name, or null when enable_athena is false."
  value       = var.enable_athena ? aws_athena_workgroup.cur2[0].name : null
}

output "reader_role_arn" {
  description = "ARN of the read-only IAM role, or null when create_reader_role is false."
  value       = var.create_reader_role ? aws_iam_role.reader[0].arn : null
}

output "reader_access_key_id" {
  description = "Access key ID for the reader IAM user, or null when create_reader_user is false."
  value       = var.create_reader_user ? aws_iam_access_key.reader[0].id : null
  sensitive   = true
}

output "reader_secret_access_key" {
  description = "Secret access key for the reader IAM user, or null when create_reader_user is false."
  value       = var.create_reader_user ? aws_iam_access_key.reader[0].secret : null
  sensitive   = true
}
