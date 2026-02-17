# =============================================================================
# Athena Views for Fixing Misaligned Columns
# =============================================================================
#
# Some CUR reports have misaligned columns due to an OpenCSVSerDe bug.
# This occurs when the invoicing entity contains a comma (e.g., "Amazon Web Services, Inc.")
# which causes the CSV parser to incorrectly split the field into two columns,
# shifting all subsequent columns by +1.
#
# These named queries create views that:
# 1. Concatenate the incorrectly split invoicing entity columns
# 2. Shift all subsequent columns back to their correct positions
#
# To use: Run the named query in Athena console to create the view,
# then query the view instead of the raw table.
# =============================================================================

# View definition for fixing misaligned columns
resource "aws_athena_named_query" "fix_misaligned_view" {
  for_each = local.accounts_needing_fix

  name        = "create_${each.key}_fixed_view"
  database    = aws_glue_catalog_database.cur_database.name
  workgroup   = aws_athena_workgroup.cur_analysis.name
  description = "Creates a view to fix misaligned columns in ${each.key} table caused by OpenCSVSerDe bug"

  query = <<-EOQ
    CREATE OR REPLACE VIEW ${replace(each.key, "-", "_")}_fixed AS
    SELECT
      -- Fix identity columns (OK, not affected by misalignment)
      "identity/lineitemid" AS line_item_id,
      "identity/timeinterval" AS time_interval,

      -- Fix bill columns (CAST invoice_id to handle schema changes from Glue crawler)
      CAST("bill/invoiceid" AS VARCHAR) AS invoice_id,
      CONCAT(
        TRIM(BOTH '"' FROM "bill/invoicingentity"),
        ',',
        TRIM(BOTH '"' FROM "bill/billingentity")
      ) AS invoicing_entity,
      "bill/billtype" AS billing_entity,
      "bill/payeraccountid" AS bill_type,
      "bill/billingperiodstartdate" AS payer_account_id,
      "bill/billingperiodenddate" AS billing_period_start_date,

      -- Fix lineitem columns (all shifted by +1)
      "lineitem/usageaccountid" AS billing_period_end_date,
      "lineitem/lineitemtype" AS usage_account_id,
      "lineitem/usagestartdate" AS line_item_type,
      "lineitem/usageenddate" AS usage_start_date,
      "lineitem/productcode" AS usage_end_date,
      "lineitem/usagetype" AS product_code,
      "lineitem/operation" AS usage_type,
      "lineitem/availabilityzone" AS operation,
      "lineitem/resourceid" AS availability_zone,
      "lineitem/usageamount" AS resource_id,
      "lineitem/normalizationfactor" AS usage_amount,
      "lineitem/normalizedusageamount" AS normalization_factor,
      "lineitem/currencycode" AS normalized_usage_amount,
      "lineitem/unblendedrate" AS currency_code,
      "lineitem/unblendedcost" AS unblended_rate,
      "lineitem/blendedrate" AS unblended_cost,
      "lineitem/blendedcost" AS blended_rate,
      "lineitem/lineitemdescription" AS blended_cost,
      "lineitem/taxtype" AS line_item_description,
      "lineitem/legalentity" AS tax_type,

      -- Fix product columns (all shifted by +1)
      "product/productname" AS legal_entity,
      "product/alarmtype" AS product_name,
      "product/servicename" AS service_name,

      -- Fix pricing columns (all shifted by +1)
      "pricing/ratecode" AS pricing_rate_code,
      "pricing/rateid" AS pricing_rate_id,
      "pricing/currency" AS pricing_currency,
      "pricing/publicondemandcost" AS pricing_public_ondemand_cost,
      "pricing/publicondemandrate" AS pricing_public_ondemand_rate,
      "pricing/term" AS pricing_term,
      "pricing/unit" AS pricing_unit

      -- Note: Add more columns as needed for your analysis
    FROM ${replace(each.key, "-", "_")}
  EOQ
}

# Named query to create a simplified cost analysis view
resource "aws_athena_named_query" "cost_analysis_view" {
  for_each = local.accounts_needing_fix

  name        = "create_${each.key}_cost_view"
  database    = aws_glue_catalog_database.cur_database.name
  workgroup   = aws_athena_workgroup.cur_analysis.name
  description = "Creates a simplified cost analysis view for ${each.key}"

  query = <<-EOQ
    CREATE OR REPLACE VIEW ${replace(each.key, "-", "_")}_cost AS
    SELECT
      -- Source account identifier
      '${replace(each.key, "-", "_")}' AS source_account,

      -- Fix and extract key cost fields
      CONCAT(
        TRIM(BOTH '"' FROM "bill/invoicingentity"),
        ',',
        TRIM(BOTH '"' FROM "bill/billingentity")
      ) AS invoicing_entity,
      "bill/payeraccountid" AS bill_type,
      "bill/billingperiodstartdate" AS payer_account_id,

      -- Correctly mapped usage fields
      "lineitem/lineitemtype" AS usage_account_id,
      "lineitem/usagestartdate" AS line_item_type,
      "lineitem/usageenddate" AS usage_start_date,
      "lineitem/productcode" AS usage_end_date,

      -- Cost fields (shifted by +1)
      TRY_CAST("lineitem/unblendedrate" AS DOUBLE) AS currency_code,
      TRY_CAST("lineitem/unblendedcost" AS DOUBLE) AS unblended_rate,
      TRY_CAST("lineitem/blendedrate" AS DOUBLE) AS unblended_cost,
      TRY_CAST("lineitem/blendedcost" AS DOUBLE) AS blended_rate,

      -- Service information
      "product/productname" AS legal_entity,
      "product/alarmtype" AS product_name
    FROM ${replace(each.key, "-", "_")}
    WHERE "lineitem/usagestartdate" != 'Tax'  -- Filter out header-like rows
  EOQ
}
