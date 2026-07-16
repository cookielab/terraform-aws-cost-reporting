output "workgroup_name" {
  description = "Name of the Athena workgroup for CUR analysis"
  value       = aws_athena_workgroup.cur_analysis.name
}

output "glue_database_name" {
  description = "Name of the Glue catalog database for CUR 2.0 data"
  value       = aws_glue_catalog_database.cur2.name
}

output "crawler_name" {
  description = "Name of the Glue crawler that owns the cur2 table"
  value       = aws_glue_crawler.cur2.name
}

output "athena_results_bucket_arn" {
  description = "ARN of the Athena query results bucket"
  value       = module.athena_results_bucket.s3_bucket_arn
}
