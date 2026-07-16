data "aws_iam_policy_document" "reader_assume" {
  count = var.create_reader_role ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    dynamic "condition" {
      for_each = var.require_mfa_for_reader_role ? [1] : []
      content {
        test     = "Bool"
        variable = "aws:MultiFactorAuthPresent"
        values   = ["true"]
      }
    }
  }
}

data "aws_iam_policy_document" "reader_access" {
  statement {
    sid    = "S3ReadAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [local.bucket_arn, "${local.bucket_arn}/*"]
  }

  statement {
    sid    = "GlueReadAccess"
    effect = "Allow"

    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchGetPartition",
    ]

    resources = [
      "arn:aws:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:catalog",
      aws_glue_catalog_database.cur2.arn,
      "arn:aws:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.cur2.name}/*",
    ]
  }

  dynamic "statement" {
    for_each = var.enable_athena ? [1] : []
    content {
      sid    = "AthenaAccess"
      effect = "Allow"

      actions = [
        "athena:GetWorkGroup",
        "athena:StartQueryExecution",
        "athena:StopQueryExecution",
        "athena:GetQueryExecution",
        "athena:GetQueryResults",
        "athena:GetQueryResultsStream",
        "athena:ListQueryExecutions",
        "athena:BatchGetQueryExecution",
      ]

      resources = ["arn:aws:athena:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:workgroup/${var.athena_workgroup_name}"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_athena ? [1] : []
    content {
      sid    = "AthenaDiscovery"
      effect = "Allow"

      actions = [
        "athena:ListDatabases",
        "athena:ListDataCatalogs",
        "athena:ListWorkGroups",
        "athena:ListTableMetadata",
        "athena:GetTableMetadata",
      ]

      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = var.enable_athena ? [1] : []
    content {
      sid    = "AthenaResultsBucketAccess"
      effect = "Allow"

      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
      ]

      resources = [
        module.athena_results_bucket[0].s3_bucket_arn,
        "${module.athena_results_bucket[0].s3_bucket_arn}/*",
      ]
    }
  }
}

resource "aws_iam_role" "reader" {
  count = var.create_reader_role ? 1 : 0

  name               = "${var.reader_name_prefix}-reader-role"
  assume_role_policy = data.aws_iam_policy_document.reader_assume[0].json

  tags = merge(var.tags, {
    ManagedBy = "Terraform"
  })
}

resource "aws_iam_role_policy" "reader" {
  count = var.create_reader_role ? 1 : 0

  name   = "${var.reader_name_prefix}-reader-access"
  role   = aws_iam_role.reader[0].id
  policy = data.aws_iam_policy_document.reader_access.json
}

resource "aws_iam_user" "reader" {
  count = var.create_reader_user ? 1 : 0

  name = "svc-${var.reader_name_prefix}-reader"

  tags = merge(var.tags, {
    ManagedBy = "Terraform"
  })
}

resource "aws_iam_access_key" "reader" {
  count = var.create_reader_user ? 1 : 0

  user = aws_iam_user.reader[0].name
}

resource "aws_iam_user_policy" "reader" {
  count = var.create_reader_user ? 1 : 0

  name   = "${var.reader_name_prefix}-reader-access"
  user   = aws_iam_user.reader[0].name
  policy = data.aws_iam_policy_document.reader_access.json
}
