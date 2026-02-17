data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Local Values
# =============================================================================

locals {
  bucket_name = coalesce(var.s3_bucket_name, "cur-csv-${data.aws_caller_identity.current.account_id}")
  bucket_arn  = "arn:aws:s3:::${local.bucket_name}"
}

# =============================================================================
# IAM Policy Documents
# =============================================================================

# Policy for AWS Billing service to write CUR reports + Lambda to read
data "aws_iam_policy_document" "bucket_policy" {
  # Allow AWS Billing service to check bucket ACL
  statement {
    sid    = "AllowBillingGetBucketAcl"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketPolicy"
    ]

    resources = [local.bucket_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cur_report_definition.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # Allow AWS Billing service to write CUR reports
  statement {
    sid    = "AllowBillingPutObject"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = ["${local.bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cur_report_definition.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # Allow Lambda from target account to read CUR reports
  statement {
    sid    = "AllowCrossAccountLambdaRead"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.lambda_function_role_arn]
    }

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket"
    ]

    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*"
    ]
  }
}

# =============================================================================
# S3 Bucket for CUR reports
# =============================================================================

module "cur_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "4.11.0"

  bucket = local.bucket_name

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  lifecycle_rule = [
    {
      id     = "transition_old_reports"
      status = "Enabled"

      filter = {
        prefix = ""
      }

      transition = [
        {
          days          = var.s3_bucket_lifecycle.transition_to_ia_days
          storage_class = "STANDARD_IA"
        },
        {
          days          = var.s3_bucket_lifecycle.transition_to_glacier_days
          storage_class = "GLACIER"
        }
      ]

      abort_incomplete_multipart_upload_days = 7
    },
    {
      id     = "expire_old_versions"
      status = "Enabled"

      filter = {
        prefix = ""
      }

      noncurrent_version_expiration = {
        noncurrent_days = 30
      }
    }
  ]

  attach_policy = true
  policy        = data.aws_iam_policy_document.bucket_policy.json

  tags = merge(var.tags, {
    Name    = "CUR Reports"
    Purpose = "AWS Cost and Usage Reports"
  })
}

# =============================================================================
# CUR Report Definition (must be in us-east-1)
# =============================================================================

resource "aws_cur_report_definition" "this" {
  provider = aws.us_east_1

  report_name                = "${lower(var.cur_time_unit)}-cur-${lower(var.cur_format)}-${data.aws_caller_identity.current.account_id}"
  time_unit                  = var.cur_time_unit
  format                     = var.cur_format
  compression                = var.cur_compression
  additional_schema_elements = ["RESOURCES", "SPLIT_COST_ALLOCATION_DATA"]
  s3_bucket                  = module.cur_bucket.s3_bucket_id
  s3_region                  = data.aws_region.current.name
  s3_prefix                  = "cur-reports"

  report_versioning      = "CREATE_NEW_REPORT"
  refresh_closed_reports = true

  tags = var.tags
}

# =============================================================================
# S3 Event Notification to invoke Lambda in target account
# =============================================================================
# Note: Lambda permission is managed in the target module

resource "aws_s3_bucket_notification" "cur" {
  bucket = module.cur_bucket.s3_bucket_id

  lambda_function {
    lambda_function_arn = var.lambda_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "${aws_cur_report_definition.this.s3_prefix}/"
  }
}
