# =============================================================================
# Glue Catalog Database
# =============================================================================

resource "aws_glue_catalog_database" "cur2" {
  name        = var.glue_database_name
  description = "Database for CUR 2.0 Data Exports aggregated from all source accounts"
}

# =============================================================================
# Glue Crawler
# =============================================================================
#
# Owns the `cur2` table end-to-end: on each run it discovers new
# BILLING_PERIOD partitions and reconciles the schema (MergeNewColumns).
# The initial table is created by the crawler's first run, so nothing here
# defines table columns -- the source Data Export is the single source of truth.
# =============================================================================

data "aws_iam_policy_document" "crawler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "crawler_access" {
  statement {
    sid    = "ReadCur2Objects"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetObject",
    ]

    resources = [
      var.cur_bucket_arn,
      "${var.cur_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "GlueCatalogWrite"
    effect = "Allow"

    actions = [
      "glue:GetDatabase",
      "glue:UpdateDatabase",
      "glue:CreateTable",
      "glue:UpdateTable",
      "glue:GetTable",
      "glue:GetTables",
      "glue:BatchCreatePartition",
      "glue:BatchDeletePartition",
      "glue:BatchGetPartition",
      "glue:CreatePartition",
      "glue:DeletePartition",
      "glue:UpdatePartition",
      "glue:GetPartition",
      "glue:GetPartitions",
    ]

    resources = [
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/${var.glue_database_name}",
      "arn:aws:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.glue_database_name}/*",
    ]
  }

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"]
  }
}

resource "aws_iam_role" "crawler" {
  name               = "${var.glue_database_name}-crawler-role"
  assume_role_policy = data.aws_iam_policy_document.crawler_assume.json

  tags = merge(var.tags, {
    ManagedBy = "Terraform"
  })
}

resource "aws_iam_role_policy" "crawler" {
  name   = "${var.glue_database_name}-crawler-access"
  role   = aws_iam_role.crawler.id
  policy = data.aws_iam_policy_document.crawler_access.json
}

resource "aws_glue_crawler" "cur2" {
  name          = "${var.glue_database_name}-crawler"
  role          = aws_iam_role.crawler.arn
  database_name = aws_glue_catalog_database.cur2.name
  description   = "Discovers CUR 2.0 partitions and reconciles the table schema"

  s3_target {
    path = "s3://${var.cur_bucket_id}/${var.data_export_prefix}"

    exclusions = [
      "**.json",
      "**.yml",
      "**.sql",
      "**.csv",
      "**.csv.metadata",
      "**.gz",
      "**.zip",
      "**/cost_and_usage_data_status/*",
      "**/metadata/**",
      "aws-programmatic-access-test-object",
    ]
  }

  schedule = var.crawler_schedule

  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Tables = {
        AddOrUpdateBehavior = "MergeNewColumns"
      }
    }
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  tags = merge(var.tags, {
    ManagedBy = "Terraform"
  })
}
