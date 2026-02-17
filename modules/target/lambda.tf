# =============================================================================
# Lambda Function for CUR Forwarding
# =============================================================================

module "lambda_forwarder" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 6.0"

  function_name = var.lambda_function_name
  description   = "Forwards CUR reports from source accounts to central bucket"
  handler       = "cur_forwarder.handler"
  runtime       = "python3.12"

  source_path = "${path.module}/lambda"
  hash_extra  = var.lambda_function_name

  # Use S3 for Lambda artifacts if bucket is available
  store_on_s3 = local.use_s3_for_lambda
  s3_bucket   = local.use_s3_for_lambda ? local.lambda_builds_bucket : null
  s3_prefix   = local.use_s3_for_lambda ? "lambda-builds/" : null

  timeout     = 300
  memory_size = 256

  environment_variables = merge(
    {
      DESTINATION_BUCKET = local.cur_bucket_id
      PREFIX_MAPPING = jsonencode({
        for k, v in local.source_accounts_full : v.bucket_name => {
          source_prefix      = v.source_prefix
          destination_prefix = v.destination_prefix
        }
      })
    },
    var.glue_database_name != "" ? {
      GLUE_DATABASE = var.glue_database_name
      GLUE_REGION   = var.glue_region
      TABLE_MAPPING = jsonencode(var.table_mapping)
    } : {}
  )

  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.lambda_execution.json

  cloudwatch_logs_retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name      = "CUR Forwarder"
    Purpose   = "Forward CUR reports from source accounts"
    ManagedBy = "Terraform"
  })
}

# Lambda permissions for S3 invocation from source accounts
resource "aws_lambda_permission" "allow_s3" {
  for_each = local.source_accounts_full

  statement_id   = "AllowS3Invoke-${each.key}"
  action         = "lambda:InvokeFunction"
  function_name  = module.lambda_forwarder.lambda_function_name
  principal      = "s3.amazonaws.com"
  source_arn     = each.value.bucket_arn
  source_account = each.value.account_id
}
