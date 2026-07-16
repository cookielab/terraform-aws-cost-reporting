# =============================================================================
# CUR 2.0 Target Module - Central S3 Bucket & Cross-Account Bucket Policy
# =============================================================================

# Bucket policy authorizing every source account's CUR 2.0 export to write
# reports into this bucket. Mirrors the required policy from the AWS docs:
# https://docs.aws.amazon.com/cur/latest/userguide/dataexports-s3-bucket.html
# One combined statement for all authorized accounts (each account's export ARN
# embeds its own account ID, so the ArnLike + SourceAccount lists cannot be
# mixed across accounts).
data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid    = "EnableAWSDataExportsToWriteToS3"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["bcm-data-exports.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${local.bucket_arn}/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = local.source_arn_patterns
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = local.authorized_account_ids
    }
  }
}

module "cur_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.14.1"

  bucket = var.bucket_name

  # Share the durability properties of the current source/target buckets:
  # versioning + SSE + fully private.
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

  # Disable ACLs (recommended by the Data Exports docs) so delivered objects are
  # owned by the bucket owner and access is controlled purely by the policy.
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  attach_policy = true
  policy        = data.aws_iam_policy_document.bucket_policy.json

  # CUR reports are the source of truth and are NEVER expired. Lifecycle mirrors
  # the CID/CUDOS data bucket: reclaim old non-current versions and clean up
  # incomplete multipart uploads / expired delete markers. Transitions to
  # cheaper storage are opt-in.
  lifecycle_rule = concat(
    var.enable_lifecycle_transitions ? [
      {
        id     = "transition_to_cheaper_storage"
        status = "Enabled"

        filter = { prefix = "" }

        transition = [
          {
            days          = var.lifecycle_transitions.transition_ia_days
            storage_class = "STANDARD_IA"
          },
          {
            days          = var.lifecycle_transitions.transition_glacier_days
            storage_class = "GLACIER"
          },
        ]
      }
    ] : [],
    [
      {
        id     = "RemoveNonCurrentVersions"
        status = "Enabled"

        filter = { prefix = "" }

        noncurrent_version_expiration = {
          newer_noncurrent_versions = var.noncurrent_versions_to_keep
          noncurrent_days           = var.noncurrent_version_expiration_days
        }
      },
      {
        id     = "DeleteIncompleteMultipartUploadsAndExpiredDeleteMarkers"
        status = "Enabled"

        filter = { prefix = "" }

        abort_incomplete_multipart_upload_days = var.abort_multipart_days

        expiration = {
          expired_object_delete_marker = true
        }
      }
    ],
  )

  tags = merge(var.tags, {
    Name      = "Aggregated CUR 2.0 Reports"
    Purpose   = "Central storage for AWS CUR 2.0 BCM Data Exports from multiple source accounts"
    ManagedBy = "Terraform"
  })
}
