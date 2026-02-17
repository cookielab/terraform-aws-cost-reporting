# =============================================================================
# CUR Reports S3 Bucket (Target Account)
# =============================================================================

# IAM Policy Document for bucket policy
data "aws_iam_policy_document" "cur_bucket_policy" {
  count = var.create_bucket ? 1 : 0

  statement {
    sid    = "AllowCrossAccountLambdaWrite"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [for k, v in local.source_accounts_full : "arn:aws:iam::${v.account_id}:root"]
    }

    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]

    resources = ["arn:aws:s3:::${var.cur_reports_bucket_name}/*"]
  }
}

module "cur_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.15.2"

  count = var.create_bucket ? 1 : 0

  bucket = var.cur_reports_bucket_name

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

  # CUR reports lifecycle - NEVER delete
  # Transitions to cheaper storage only when enable_lifecycle_transitions = true
  lifecycle_rule = concat(
    # Transition to cheaper storage (optional)
    var.enable_lifecycle_transitions ? [
      {
        id     = "transition_to_cheaper_storage"
        status = "Enabled"

        filter = {
          prefix = ""
        }

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

        # NO expiration - keep reports forever

        abort_incomplete_multipart_upload_days = 7
      }
    ] : [],
    # Always expire lambda builds
    [
      {
        id     = "expire_lambda_builds"
        status = "Enabled"

        filter = {
          prefix = "lambda-builds/"
        }

        expiration = {
          days = 30
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
    Name      = "Aggregated CUR Reports"
    Purpose   = "Central storage for AWS Cost and Usage Reports from multiple source accounts"
    ManagedBy = "Terraform"
  })
}
