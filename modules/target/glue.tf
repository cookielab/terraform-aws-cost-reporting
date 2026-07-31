# =============================================================================
# CUR 2.0 Target Module - Glue Catalog & Crawler
# =============================================================================
# Mirrors the CID data-exports aggregation template so CID SQL queries and
# dashboards work unchanged against this table.
#
# Source: aws-solutions-library-samples/cloud-intelligence-dashboards-data-collection
#         data-exports/deploy/data-exports-aggregation.yaml @ f73fd0743b6a
#
# The table is created here with named partition keys and the CID column set.
# The crawler then only ADDS partitions and reconciles new columns -- it never
# renames the partition keys, because the table already declares them. That is
# the whole reason the table is pre-created rather than left to the crawler:
# a crawler discovering `cur2/<account>/cur2/data/BILLING_PERIOD=...` on its own
# would name the first three levels partition_0..partition_2.
# =============================================================================

locals {
  cur2_columns = jsondecode(file("${path.module}/cur2_columns.json"))

  # Table location. Only the `cur2/` prefix is part of the table -- the legacy
  # flat-layout streamedge export at `<account_id>/data/...` sits outside it and
  # is therefore invisible to both the table and the crawler.
  glue_table_location = "s3://${var.bucket_name}/cur2/"
}

# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------

resource "aws_glue_catalog_database" "cur2" {
  name        = var.glue_database_name
  description = "CUR 2.0 (BCM Data Exports) reports from all source accounts"

  tags = merge(var.tags, {
    Name = var.glue_database_name
  })
}

# -----------------------------------------------------------------------------
# Table
# -----------------------------------------------------------------------------

resource "aws_glue_catalog_table" "cur2" {
  name          = var.glue_table_name
  database_name = aws_glue_catalog_database.cur2.name
  description   = "CUR 2.0 Parquet reports, partitioned by source account and billing period"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification  = "parquet"
    compressionType = "none"
  }

  dynamic "partition_keys" {
    for_each = local.cur2_columns.partition_keys
    content {
      name = partition_keys.value.name
      type = partition_keys.value.type
    }
  }

  storage_descriptor {
    location      = local.glue_table_location
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    # ParquetHiveSerDe resolves columns by name and returns NULL for ones absent
    # from a given file, so the table can declare the full CID column set even
    # for accounts whose export omits a conditional group.
    dynamic "columns" {
      for_each = local.cur2_columns.table_columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }

  # The crawler owns the table after first run (MergeNewColumns): besides the
  # schema and table parameters it also rewrites owner, the storage descriptor's
  # own parameters (CrawlerSchema*, recordCount, sizeKey, ...), number_of_buckets
  # and drops the SerDe name on every crawl. Terraform must not fight any of it,
  # or every crawl re-creates the same plan drift.
  lifecycle {
    ignore_changes = [
      owner,
      parameters,
      storage_descriptor[0].columns,
      storage_descriptor[0].number_of_buckets,
      storage_descriptor[0].parameters,
      storage_descriptor[0].ser_de_info[0].name,
    ]
  }
}

# -----------------------------------------------------------------------------
# Crawler IAM role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "crawler_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "crawler" {
  name               = var.crawler_role_name
  description        = "Role assumed by the CUR 2.0 Glue crawler"
  assume_role_policy = data.aws_iam_policy_document.crawler_assume_role.json

  tags = merge(var.tags, {
    Name = var.crawler_role_name
  })
}

data "aws_iam_policy_document" "crawler" {
  statement {
    sid    = "ReadCur2Objects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]

    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
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
      "glue:CreatePartition",
      "glue:DeletePartition",
      "glue:BatchDeletePartition",
      "glue:UpdatePartition",
      "glue:GetPartition",
      "glue:GetPartitions",
      "glue:BatchGetPartition",
    ]

    resources = [
      "arn:aws:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:aws:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:database/${aws_glue_catalog_database.cur2.name}",
      "arn:aws:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.cur2.name}/*",
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

    resources = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws-glue/*"]
  }
}

resource "aws_iam_role_policy" "crawler" {
  name   = "cur2-crawler-access"
  role   = aws_iam_role.crawler.id
  policy = data.aws_iam_policy_document.crawler.json
}

# -----------------------------------------------------------------------------
# Crawler
# -----------------------------------------------------------------------------

resource "aws_glue_crawler" "cur2" {
  name          = var.crawler_name
  description   = "Discovers CUR 2.0 partitions and reconciles the table schema"
  role          = aws_iam_role.crawler.arn
  database_name = aws_glue_catalog_database.cur2.name
  schedule      = var.crawler_schedule

  s3_target {
    path = local.glue_table_location

    # Verbatim from CID. `**/metadata/**` keeps the per-export Manifest.json out
    # of the table, and the test object is what BCM Data Exports drops in the
    # bucket to prove it can write cross-account.
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

  # CRAWL_EVERYTHING (not CRAWL_NEW_FOLDERS_ONLY): OVERWRITE_REPORT rewrites the
  # current billing period's files in place, so already-crawled folders change.
  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }

  # DeleteBehavior LOG: never drop a partition or table just because its objects
  # went missing during a crawl.
  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
    CrawlerOutput = {
      Tables = {
        AddOrUpdateBehavior = "MergeNewColumns"
      }
    }
  })

  tags = merge(var.tags, {
    Name = var.crawler_name
  })

  depends_on = [
    aws_iam_role_policy.crawler,
    aws_glue_catalog_table.cur2,
  ]
}
