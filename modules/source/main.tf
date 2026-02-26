data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# =============================================================================
# Local Values
# =============================================================================

locals {
  bucket_name = coalesce(var.s3_bucket_name, "cur-csv-${data.aws_caller_identity.current.account_id}")
  bucket_arn  = "arn:aws:s3:::${local.bucket_name}"
  bucket_id   = var.create_bucket ? module.cur_bucket[0].s3_bucket_id : local.bucket_name

  cur_s3_prefix = var.create_report ? aws_cur_report_definition.this[0].s3_prefix : var.cur_s3_prefix

  sns_topic_name = coalesce(var.sns_topic_name, "cur-notifications-${data.aws_caller_identity.current.account_id}")
}

# =============================================================================
# IAM Policy Documents
# =============================================================================

# Bucket policy: Billing service write + Lambda cross-account read
data "aws_iam_policy_document" "bucket_policy" {
  # Allow AWS Billing service to check bucket ACL
  dynamic "statement" {
    for_each = var.create_report ? [1] : []
    content {
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
        values   = [aws_cur_report_definition.this[0].arn]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }

  # Allow AWS Billing service to write CUR reports
  dynamic "statement" {
    for_each = var.create_report ? [1] : []
    content {
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
        values   = [aws_cur_report_definition.this[0].arn]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
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
# S3 Bucket for CUR reports (optional)
# =============================================================================

module "cur_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "4.11.0"

  count = var.create_bucket ? 1 : 0

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

# Attach bucket policy to existing bucket (when create_bucket = false)
resource "aws_s3_bucket_policy" "existing" {
  count = var.create_bucket ? 0 : 1

  bucket = local.bucket_name
  policy = data.aws_iam_policy_document.bucket_policy.json
}

# =============================================================================
# CUR Report Definition (optional, must be in us-east-1)
# =============================================================================

resource "aws_cur_report_definition" "this" {
  count    = var.create_report ? 1 : 0
  provider = aws.us_east_1

  report_name                = "${lower(var.cur_time_unit)}-cur-${lower(var.cur_format)}-${data.aws_caller_identity.current.account_id}"
  time_unit                  = var.cur_time_unit
  format                     = var.cur_format
  compression                = var.cur_compression
  additional_schema_elements = ["RESOURCES", "SPLIT_COST_ALLOCATION_DATA"]
  s3_bucket                  = local.bucket_id
  s3_region                  = data.aws_region.current.name
  s3_prefix                  = "cur-reports"

  report_versioning      = "CREATE_NEW_REPORT"
  refresh_closed_reports = true

  tags = var.tags
}

# =============================================================================
# SNS Topic for CUR notifications (optional)
# =============================================================================

resource "aws_sns_topic" "cur" {
  count = var.use_sns ? 1 : 0

  name = local.sns_topic_name

  tags = merge(var.tags, {
    Name    = "CUR Notifications"
    Purpose = "S3 event notifications for CUR reports"
  })
}

data "aws_iam_policy_document" "sns_topic_policy" {
  count = var.use_sns ? 1 : 0

  # Allow S3 to publish to SNS
  statement {
    sid    = "AllowS3Publish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.cur[0].arn]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.bucket_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  # Allow target account Lambda/SQS to subscribe
  dynamic "statement" {
    for_each = length(var.sns_subscriber_arns) > 0 ? [1] : []
    content {
      sid    = "AllowCrossAccountSubscribe"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.sns_subscriber_arns
      }

      actions = [
        "SNS:Subscribe",
        "SNS:Receive"
      ]

      resources = [aws_sns_topic.cur[0].arn]
    }
  }
}

resource "aws_sns_topic_policy" "cur" {
  count = var.use_sns ? 1 : 0

  arn    = aws_sns_topic.cur[0].arn
  policy = data.aws_iam_policy_document.sns_topic_policy[0].json
}

# =============================================================================
# S3 Event Notification
# =============================================================================

resource "aws_s3_bucket_notification" "cur" {
  bucket = local.bucket_id

  # Direct Lambda invocation
  dynamic "lambda_function" {
    for_each = var.use_sns ? [] : [1]
    content {
      lambda_function_arn = var.lambda_function_arn
      events              = ["s3:ObjectCreated:*"]
      filter_prefix       = "${local.cur_s3_prefix}/"
    }
  }

  # SNS notification
  dynamic "topic" {
    for_each = var.use_sns ? [1] : []
    content {
      topic_arn     = aws_sns_topic.cur[0].arn
      events        = ["s3:ObjectCreated:*"]
      filter_prefix = "${local.cur_s3_prefix}/"
    }
  }
}
