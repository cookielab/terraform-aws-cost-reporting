output "bucket_id" {
  description = "ID of the CUR S3 bucket"
  value       = local.bucket_id
}

output "bucket_arn" {
  description = "ARN of the CUR S3 bucket"
  value       = local.bucket_arn
}

output "bucket_name" {
  description = "Name of the CUR S3 bucket"
  value       = local.bucket_name
}

output "cur_report_name" {
  description = "Name of the CUR report"
  value       = var.create_report ? aws_cur_report_definition.this[0].report_name : null
}

output "cur_prefix" {
  description = "S3 prefix where CUR reports are stored"
  value       = local.cur_s3_prefix
}

output "account_id" {
  description = "AWS Account ID where this module is deployed"
  value       = data.aws_caller_identity.current.account_id
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for CUR notifications (null if use_sns = false)"
  value       = var.use_sns ? aws_sns_topic.cur[0].arn : null
}
