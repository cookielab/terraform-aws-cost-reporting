output "workgroup_name" {
  description = "Name of the Athena workgroup for CUR analysis"
  value       = aws_athena_workgroup.cur_analysis.name
}

output "glue_database_name" {
  description = "Name of the Glue catalog database for CUR data"
  value       = aws_glue_catalog_database.cur_database.name
}

output "athena_results_bucket_arn" {
  description = "ARN of the Athena query results bucket"
  value       = module.athena_results_bucket.s3_bucket_arn
}
