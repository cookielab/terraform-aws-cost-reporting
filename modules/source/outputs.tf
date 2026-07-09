# =============================================================================
# CUR 2.0 Source Module - Outputs
# =============================================================================

output "export_arn" {
  description = "ARN of the CUR 2.0 export (the Cloud Control primary identifier)."
  value       = aws_cloudcontrolapi_resource.cur2_export.id
}

output "export_name" {
  description = "Name of the export. Also the value of the report_name Glue partition."
  value       = var.export_name
}

output "account_id" {
  description = "AWS account ID this export was created in. Also the value of the source_account_id Glue partition."
  value       = local.account_id
}

output "s3_prefix" {
  description = "Prefix under the destination bucket the export writes to."
  value       = local.s3_prefix
}

output "s3_destination" {
  description = "Root S3 path the reports are written under. The data/ and metadata/ partitions live below this."
  value       = "s3://${var.destination_bucket}/${local.s3_prefix}/${var.export_name}/"
}

output "query_columns" {
  description = "Columns selected by the export, after applying the INCLUDE_* toggles."
  value       = local.query_columns
}
