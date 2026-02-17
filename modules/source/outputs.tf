output "bucket_id" {
  description = "ID of the CUR S3 bucket"
  value       = module.cur_bucket.s3_bucket_id
}

output "bucket_arn" {
  description = "ARN of the CUR S3 bucket"
  value       = module.cur_bucket.s3_bucket_arn
}

output "bucket_name" {
  description = "Name of the CUR S3 bucket"
  value       = module.cur_bucket.s3_bucket_id
}

output "cur_report_name" {
  description = "Name of the CUR report"
  value       = aws_cur_report_definition.this.report_name
}

output "cur_prefix" {
  description = "S3 prefix where CUR reports are stored"
  value       = aws_cur_report_definition.this.s3_prefix
}

output "account_id" {
  description = "AWS Account ID where this module is deployed"
  value       = data.aws_caller_identity.current.account_id
}
