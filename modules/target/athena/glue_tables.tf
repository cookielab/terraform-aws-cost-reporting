# =============================================================================
# Glue Catalog Tables (one per source account)
# =============================================================================
#
# Static table definitions for CUR data. Partitions are managed by the Lambda
# function which detects Manifest.json files and creates/updates partitions
# pointing to the latest snapshot for each billing period.
#
# OpenCSVSerDe maps columns by position (not name), so we define the standard
# CUR columns in order. Extra columns in the CSV beyond what's defined here
# are silently ignored.
# =============================================================================

resource "aws_glue_catalog_table" "cur_table" {
  for_each = var.source_accounts

  database_name = aws_glue_catalog_database.cur_database.name
  name          = replace(each.key, "-", "_")
  description   = "CUR data for ${each.key} (account ${each.value.account_id})"
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"         = "csv"
    "skip.header.line.count" = "1"
    "EXTERNAL"               = "TRUE"
  }

  storage_descriptor {
    location      = "s3://${var.cur_bucket_id}/${each.value.destination_prefix}"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.serde2.OpenCSVSerde"

      parameters = {
        "separatorChar" = ","
        "quoteChar"     = "\""
        "escapeChar"    = "\\"
      }
    }

    # Standard CUR columns (positional mapping via OpenCSVSerDe)
    # These are the first 29 columns common to all CUR reports.
    columns {
      name = "identity/lineitemid"
      type = "string"
    }
    columns {
      name = "identity/timeinterval"
      type = "string"
    }
    columns {
      name = "bill/invoiceid"
      type = "string"
    }
    columns {
      name = "bill/invoicingentity"
      type = "string"
    }
    columns {
      name = "bill/billingentity"
      type = "string"
    }
    columns {
      name = "bill/billtype"
      type = "string"
    }
    columns {
      name = "bill/payeraccountid"
      type = "string"
    }
    columns {
      name = "bill/billingperiodstartdate"
      type = "string"
    }
    columns {
      name = "bill/billingperiodenddate"
      type = "string"
    }
    columns {
      name = "lineitem/usageaccountid"
      type = "string"
    }
    columns {
      name = "lineitem/lineitemtype"
      type = "string"
    }
    columns {
      name = "lineitem/usagestartdate"
      type = "string"
    }
    columns {
      name = "lineitem/usageenddate"
      type = "string"
    }
    columns {
      name = "lineitem/productcode"
      type = "string"
    }
    columns {
      name = "lineitem/usagetype"
      type = "string"
    }
    columns {
      name = "lineitem/operation"
      type = "string"
    }
    columns {
      name = "lineitem/availabilityzone"
      type = "string"
    }
    columns {
      name = "lineitem/resourceid"
      type = "string"
    }
    columns {
      name = "lineitem/usageamount"
      type = "string"
    }
    columns {
      name = "lineitem/normalizationfactor"
      type = "string"
    }
    columns {
      name = "lineitem/normalizedusageamount"
      type = "string"
    }
    columns {
      name = "lineitem/currencycode"
      type = "string"
    }
    columns {
      name = "lineitem/unblendedrate"
      type = "string"
    }
    columns {
      name = "lineitem/unblendedcost"
      type = "string"
    }
    columns {
      name = "lineitem/blendedrate"
      type = "string"
    }
    columns {
      name = "lineitem/blendedcost"
      type = "string"
    }
    columns {
      name = "lineitem/lineitemdescription"
      type = "string"
    }
    columns {
      name = "lineitem/taxtype"
      type = "string"
    }
    columns {
      name = "lineitem/legalentity"
      type = "string"
    }
  }

  partition_keys {
    name = "billing_period"
    type = "string"
  }
}
