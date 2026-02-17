# =============================================================================
# Data Sources and IAM Policy Documents
# =============================================================================

# Lambda execution policy
data "aws_iam_policy_document" "lambda_execution" {
  # Read from source buckets
  statement {
    sid    = "ReadFromSourceBuckets"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]

    resources = [for k, v in local.source_accounts_full : "${v.bucket_arn}/*"]
  }

  # List source buckets
  statement {
    sid    = "ListSourceBuckets"
    effect = "Allow"

    actions = ["s3:ListBucket"]

    resources = [for k, v in local.source_accounts_full : v.bucket_arn]
  }

  # Write to destination bucket
  statement {
    sid    = "WriteToDestinationBucket"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]

    resources = ["${local.cur_bucket_arn}/*"]
  }

  # List destination bucket
  statement {
    sid    = "ListDestinationBucket"
    effect = "Allow"

    actions = ["s3:ListBucket"]

    resources = [local.cur_bucket_arn]
  }

  # Read from destination bucket (Lambda reads Manifest.json for partition updates)
  dynamic "statement" {
    for_each = var.glue_database_name != "" ? [1] : []
    content {
      sid    = "ReadDestinationBucket"
      effect = "Allow"

      actions = ["s3:GetObject"]

      resources = ["${local.cur_bucket_arn}/*"]
    }
  }

  # Glue partition management (create/update partitions when Manifest.json is detected)
  dynamic "statement" {
    for_each = var.glue_database_name != "" ? [1] : []
    content {
      sid    = "GluePartitionManagement"
      effect = "Allow"

      actions = [
        "glue:GetTable",
        "glue:GetPartition",
        "glue:CreatePartition",
        "glue:UpdatePartition",
      ]

      resources = [
        "arn:aws:glue:${var.glue_region}:${data.aws_caller_identity.current.account_id}:catalog",
        "arn:aws:glue:${var.glue_region}:${data.aws_caller_identity.current.account_id}:database/${var.glue_database_name}",
        "arn:aws:glue:${var.glue_region}:${data.aws_caller_identity.current.account_id}:table/${var.glue_database_name}/*",
      ]
    }
  }
}
