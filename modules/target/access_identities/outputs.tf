output "reader_role_arn" {
  description = "ARN of the IAM role for read-only CUR access (for AssumeRole)"
  value       = var.create_reader_role ? aws_iam_role.cur_reader[0].arn : null
}

output "reader_access_key_id" {
  description = "AWS Access Key ID for CUR reader IAM user"
  value       = var.create_reader_user ? aws_iam_access_key.cur_reader[0].id : null
  sensitive   = true
}

output "reader_secret_access_key" {
  description = "AWS Secret Access Key for CUR reader IAM user"
  value       = var.create_reader_user ? aws_iam_access_key.cur_reader[0].secret : null
  sensitive   = true
}
