output "bucket_id" {
  description = "ID of the aggregated CUR S3 bucket"
  value       = local.cur_bucket_id
}

output "bucket_arn" {
  description = "ARN of the aggregated CUR S3 bucket"
  value       = local.cur_bucket_arn
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function (use this in source account S3 event notifications)"
  value       = module.lambda_forwarder.lambda_function_arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = module.lambda_forwarder.lambda_function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda function's IAM role (use this in source account bucket policies)"
  value       = module.lambda_forwarder.lambda_role_arn
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup for CUR analysis"
  value       = var.enable_athena ? module.athena[0].workgroup_name : null
}

output "glue_database_name" {
  description = "Name of the Glue catalog database for CUR data"
  value       = var.enable_athena ? module.athena[0].glue_database_name : null
}

output "reader_role_arn" {
  description = "ARN of the IAM role for read-only CUR access (for AssumeRole)"
  value       = var.create_reader_role ? module.access_identities[0].reader_role_arn : null
}

output "reader_access_key_id" {
  description = "AWS Access Key ID for CUR reader IAM user"
  value       = var.create_reader_user ? module.access_identities[0].reader_access_key_id : null
  sensitive   = true
}

output "reader_secret_access_key" {
  description = "AWS Secret Access Key for CUR reader IAM user"
  value       = var.create_reader_user ? module.access_identities[0].reader_secret_access_key : null
  sensitive   = true
}
