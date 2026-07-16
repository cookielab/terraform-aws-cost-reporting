# =============================================================================
# Account Map reference table
# =============================================================================
#
# A small CSV mapping account IDs to human-friendly names/clients, uploaded to
# the CUR bucket and exposed as a Glue table so queries can join cost data
# against readable account/client names. Managed only when `account_map` is set.
# =============================================================================

locals {
  account_map_enabled = length(var.account_map) > 0

  account_map_header = "account_id,account_name,client_id,client_name,payer_account_id,is_org_member,environment,active"

  account_map_rows = [
    for a in var.account_map : join(",", [
      a.account_id,
      a.account_name,
      a.client_id,
      a.client_name,
      a.payer_account_id != null ? a.payer_account_id : a.account_id,
      tostring(a.is_org_member),
      a.environment,
      tostring(a.active),
    ])
  ]

  account_map_csv = "${local.account_map_header}\n${join("\n", local.account_map_rows)}\n"
}

resource "aws_s3_object" "account_map" {
  count = local.account_map_enabled ? 1 : 0

  bucket        = var.cur_bucket_id
  key           = "reference/account_map/account_map.csv"
  content       = local.account_map_csv
  content_type  = "text/csv"
  etag          = md5(local.account_map_csv)
  storage_class = "STANDARD"
}

resource "aws_glue_catalog_table" "account_map" {
  count = local.account_map_enabled ? 1 : 0

  database_name = aws_glue_catalog_database.cur2.name
  name          = "account_map"
  description   = "Account ID to name/client mapping for cost report joins"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"         = "csv"
    "skip.header.line.count" = "1"
    "EXTERNAL"               = "TRUE"
  }

  storage_descriptor {
    location      = "s3://${var.cur_bucket_id}/reference/account_map/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"

      parameters = {
        "separatorChar" = ","
        "quoteChar"     = "\""
      }
    }

    dynamic "columns" {
      for_each = [
        "account_id", "account_name", "client_id", "client_name",
        "payer_account_id", "is_org_member", "environment", "active",
      ]
      content {
        name = columns.value
        type = "string"
      }
    }
  }
}
