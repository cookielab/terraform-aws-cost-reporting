# =============================================================================
# Read-Only IAM Role (with optional MFA requirement)
# =============================================================================

data "aws_iam_policy_document" "cur_reader_role_assume" {
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

resource "aws_iam_role" "cur_reader" {
  count = var.create_reader_role ? 1 : 0

  name               = "${var.name_prefix}-reader-role"
  assume_role_policy = data.aws_iam_policy_document.cur_reader_role_assume[0].json

  tags = merge(var.tags, {
    Purpose   = "Read-only access to CUR reports for applications and users"
    ManagedBy = "Terraform"
  })
}

resource "aws_iam_role_policy" "cur_reader_access" {
  count = var.create_reader_role ? 1 : 0

  name   = "cur-reader-access"
  role   = aws_iam_role.cur_reader[0].name
  policy = data.aws_iam_policy_document.cur_reader_access.json
}

# =============================================================================
# Read-Only IAM User (optional, for service accounts)
# =============================================================================

resource "aws_iam_user" "cur_reader" {
  count = var.create_reader_user ? 1 : 0

  name = "svc-${var.name_prefix}-reader"

  tags = merge(var.tags, {
    Purpose   = "Read-only access to CUR reports for analytics"
    ManagedBy = "Terraform"
  })
}

resource "aws_iam_access_key" "cur_reader" {
  count = var.create_reader_user ? 1 : 0

  user = aws_iam_user.cur_reader[0].name
}

resource "aws_iam_user_policy" "cur_reader_access" {
  count = var.create_reader_user ? 1 : 0

  name   = "cur-reader-access"
  user   = aws_iam_user.cur_reader[0].name
  policy = data.aws_iam_policy_document.cur_reader_access.json
}

# =============================================================================
# Reader Access Policy Document (shared by role and user)
# =============================================================================

data "aws_iam_policy_document" "cur_reader_access" {
  # S3 read access to CUR bucket
  statement {
    sid    = "S3ReadAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]

    resources = [
      var.cur_bucket_arn,
      "${var.cur_bucket_arn}/*"
    ]
  }

  # Athena access (optional)
  dynamic "statement" {
    for_each = var.enable_athena_access ? [1] : []
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
        "athena:BatchGetQueryExecution"
      ]

      resources = [
        "arn:aws:athena:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:workgroup/${var.athena_workgroup_name}"
      ]
    }
  }

  # Athena discovery permissions for Grafana UI (optional)
  dynamic "statement" {
    for_each = var.enable_athena_access ? [1] : []
    content {
      sid    = "AthenaDiscovery"
      effect = "Allow"

      actions = [
        "athena:ListDatabases",
        "athena:ListDataCatalogs",
        "athena:ListWorkGroups",
        "athena:ListTableMetadata",
        "athena:GetTableMetadata"
      ]

      resources = ["*"]
    }
  }

  # Glue access (optional)
  dynamic "statement" {
    for_each = var.enable_athena_access ? [1] : []
    content {
      sid    = "GlueReadAccess"
      effect = "Allow"

      actions = [
        "glue:GetDatabase",
        "glue:GetDatabases",
        "glue:GetTable",
        "glue:GetTables",
        "glue:GetPartition",
        "glue:GetPartitions",
        "glue:BatchGetPartition"
      ]

      resources = [
        "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
        "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/${var.glue_database_name}",
        "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.glue_database_name}/*"
      ]
    }
  }

  # Athena results bucket access (optional)
  dynamic "statement" {
    for_each = var.enable_athena_access && var.athena_results_bucket_arn != "" ? [1] : []
    content {
      sid    = "AthenaResultsBucketAccess"
      effect = "Allow"

      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ]

      resources = [
        var.athena_results_bucket_arn,
        "${var.athena_results_bucket_arn}/*"
      ]
    }
  }
}
