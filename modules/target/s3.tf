# =============================================================================
# CUR 2.0 Reports S3 Bucket (Target / central account)
# =============================================================================

# Bucket policy: allow AWS BCM Data Exports to deliver reports cross-account.
data "aws_iam_policy_document" "cur_bucket_policy" {
  count = var.create_bucket ? 1 : 0

  statement {
    sid    = "EnableAWSDataExportsToWriteToS3"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["bcm-data-exports.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.cur_reports_bucket_name}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = var.source_account_ids
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [for id in var.source_account_ids : "arn:aws:bcm-data-exports:us-east-1:${id}:export/*"]
    }
  }
}

module "cur_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.15.2"

  count = var.create_bucket ? 1 : 0

  bucket = var.cur_reports_bucket_name

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

  # CUR data is NEVER deleted; only optionally transitioned to cheaper storage.
  lifecycle_rule = concat(
    var.enable_lifecycle_transitions ? [
      {
        id     = "transition_to_cheaper_storage"
        status = "Enabled"

        filter = { prefix = "" }

        transition = [
          {
            days          = var.cur_reports_bucket_lifecycle.transition_ia_days
            storage_class = "STANDARD_IA"
          },
          {
            days          = var.cur_reports_bucket_lifecycle.transition_glacier_days
            storage_class = "GLACIER"
          }
        ]

        abort_incomplete_multipart_upload_days = 7
      }
    ] : [],
    [
      {
        id     = "expire_noncurrent_versions"
        status = "Enabled"

        filter = { prefix = "" }

        noncurrent_version_expiration = {
          noncurrent_days = 30
        }

        abort_incomplete_multipart_upload_days = 7
      }
    ]
  )

  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  attach_policy = true
  policy        = data.aws_iam_policy_document.cur_bucket_policy[0].json

  tags = merge(var.tags, {
    Name      = "Aggregated CUR 2.0 Reports"
    Purpose   = "Central storage for AWS CUR 2.0 Data Exports from multiple source accounts"
    ManagedBy = "Terraform"
  })
}
