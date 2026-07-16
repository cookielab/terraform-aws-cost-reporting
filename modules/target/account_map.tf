# =============================================================================
# CUR 2.0 Target Module - account_map reference table
# =============================================================================
# CUR reports cost per AWS account. To report it per CLIENT -- one client may own
# several accounts across several organizations, e.g. Carvago -- the cost rows
# have to be joined to a mapping AWS cannot know about.
#
# The mapping is a CSV in S3 with a Glue table over it, so Athena can join it:
#
#   SELECT m.client_name, sum(c.line_item_unblended_cost)
#   FROM account_map m
#   LEFT JOIN cur2 c ON c.line_item_usage_account_id = m.account_id
#   GROUP BY 1
#
# LEFT JOIN from account_map, not from cur2: CUR only contains accounts that
# incurred cost, so a zero-spend account would silently vanish the other way
# round.
#
# The CSV lives under `reference/`, outside the `cur2/` prefix that the crawler
# and the cur2 table cover, so it can never be mistaken for report data.
# =============================================================================

locals {
  create_account_map = length(var.account_map) > 0

  account_map_header = "account_id,account_name,client_id,client_name,payer_account_id,is_org_member,environment,active"

  # No quoting: LazySimpleSerDe cannot escape anything. A comma or newline in any
  # value would shift columns and silently misattribute cost. `var.account_map`
  # has a validation rejecting both -- do not relax it without switching SerDe.
  account_map_csv = join("\n", concat(
    [local.account_map_header],
    [for a in var.account_map :
      join(",", [
        a.account_id,
        a.account_name,
        a.client_id,
        a.client_name,
        a.payer_account_id,
        tostring(a.is_org_member),
        a.environment,
        tostring(a.active),
      ])
    ],
  ))

  # Columns are declared in the same order as the CSV. LazySimpleSerDe resolves
  # by position, not by name, so the two MUST stay in sync.
  account_map_columns = [
    { name = "account_id", type = "string" },
    { name = "account_name", type = "string" },
    { name = "client_id", type = "string" },
    { name = "client_name", type = "string" },
    { name = "payer_account_id", type = "string" },
    { name = "is_org_member", type = "boolean" },
    { name = "environment", type = "string" },
    { name = "active", type = "boolean" },
  ]
}

resource "aws_s3_object" "account_map" {
  count = local.create_account_map ? 1 : 0

  bucket       = module.cur_bucket.s3_bucket_id
  key          = "${var.account_map_prefix}/account_map.csv"
  content      = local.account_map_csv
  content_type = "text/csv"
  etag         = md5(local.account_map_csv)

  tags = merge(var.tags, {
    Name = "account_map"
  })
}

resource "aws_glue_catalog_table" "account_map" {
  count = local.create_account_map ? 1 : 0

  name          = "account_map"
  database_name = aws_glue_catalog_database.cur2.name
  description   = "Maps AWS accounts to the client that owns them"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    classification           = "csv"
    "skip.header.line.count" = "1"
  }

  storage_descriptor {
    location      = "s3://${var.bucket_name}/${var.account_map_prefix}/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "LazySimpleSerDe"
      serialization_library = "org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe"

      parameters = {
        "field.delim" = ","
      }
    }

    dynamic "columns" {
      for_each = local.account_map_columns
      content {
        name = columns.value.name
        type = columns.value.type
      }
    }
  }
}
