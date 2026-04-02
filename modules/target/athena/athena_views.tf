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

# =============================================================================
# Standard CUR View (compatible with default Grafana Athena CUR dashboard)
# =============================================================================
#
# Automatically creates a view per account that maps slash-delimited CUR
# column names (e.g. "lineitem/unblendedcost") to the underscore format
# expected by the default Grafana "Athena Cost and Usage Report" dashboard
# (e.g. line_item_unblended_cost).
#
# The view is created automatically during terraform apply. In Grafana,
# set CUR_Table to {account}_standard.
# =============================================================================

resource "null_resource" "standard_view" {
  for_each = var.source_accounts

  triggers = {
    # Recreate if table name or database changes
    table_name = replace(each.key, "-", "_")
    database   = aws_glue_catalog_database.cur_database.name
    workgroup  = aws_athena_workgroup.cur_analysis.name
    # Update hash to force recreation when view SQL changes
    view_hash = "v1"
  }

  provisioner "local-exec" {
    command = <<-EOF
      aws athena start-query-execution \
        --query-string "CREATE OR REPLACE VIEW ${aws_glue_catalog_database.cur_database.name}.${replace(each.key, "-", "_")}_standard AS SELECT \"identity/lineitemid\" AS identity_line_item_id, \"identity/timeinterval\" AS identity_time_interval, \"bill/invoiceid\" AS bill_invoice_id, \"bill/invoicingentity\" AS bill_invoicing_entity, \"bill/billingentity\" AS bill_billing_entity, \"bill/billtype\" AS bill_bill_type, \"bill/payeraccountid\" AS bill_payer_account_id, CAST(TRY(from_iso8601_timestamp(\"bill/billingperiodstartdate\")) AS timestamp) AS bill_billing_period_start_date, CAST(TRY(from_iso8601_timestamp(\"bill/billingperiodenddate\")) AS timestamp) AS bill_billing_period_end_date, \"lineitem/usageaccountid\" AS line_item_usage_account_id, \"lineitem/lineitemtype\" AS line_item_line_item_type, CAST(TRY(from_iso8601_timestamp(\"lineitem/usagestartdate\")) AS timestamp) AS line_item_usage_start_date, CAST(TRY(from_iso8601_timestamp(\"lineitem/usageenddate\")) AS timestamp) AS line_item_usage_end_date, \"lineitem/productcode\" AS line_item_product_code, \"lineitem/usagetype\" AS line_item_usage_type, \"lineitem/operation\" AS line_item_operation, \"lineitem/availabilityzone\" AS line_item_availability_zone, \"lineitem/resourceid\" AS line_item_resource_id, TRY_CAST(\"lineitem/usageamount\" AS DOUBLE) AS line_item_usage_amount, TRY_CAST(\"lineitem/normalizationfactor\" AS DOUBLE) AS line_item_normalization_factor, TRY_CAST(\"lineitem/normalizedusageamount\" AS DOUBLE) AS line_item_normalized_usage_amount, \"lineitem/currencycode\" AS line_item_currency_code, TRY_CAST(\"lineitem/unblendedrate\" AS DOUBLE) AS line_item_unblended_rate, TRY_CAST(\"lineitem/unblendedcost\" AS DOUBLE) AS line_item_unblended_cost, TRY_CAST(\"lineitem/blendedrate\" AS DOUBLE) AS line_item_blended_rate, TRY_CAST(\"lineitem/blendedcost\" AS DOUBLE) AS line_item_blended_cost, \"lineitem/lineitemdescription\" AS line_item_line_item_description, \"lineitem/taxtype\" AS line_item_tax_type, \"lineitem/legalentity\" AS line_item_legal_entity, \"product/productname\" AS product_product_name, \"product/availabilityzone\" AS product_availability_zone, \"product/instancetype\" AS product_instance_type, \"product/instancefamily\" AS product_instance_family, \"product/location\" AS product_location, \"product/locationtype\" AS product_location_type, \"product/operatingsystem\" AS product_operating_system, \"product/operation\" AS product_operation, \"product/productfamily\" AS product_product_family, \"product/region\" AS product_region, \"product/regioncode\" AS product_region_code, \"product/servicecode\" AS product_servicecode, \"product/servicename\" AS product_servicename, \"product/tenancy\" AS product_tenancy, \"product/usagetype\" AS product_usagetype, \"product/vcpu\" AS product_vcpu, \"product/memory\" AS product_memory, \"product/storage\" AS product_storage, \"product/networkperformance\" AS product_network_performance, \"product/volumetype\" AS product_volume_type, TRY_CAST(\"pricing/publicondemandcost\" AS DOUBLE) AS pricing_public_on_demand_cost, TRY_CAST(\"pricing/publicondemandrate\" AS DOUBLE) AS pricing_public_on_demand_rate, \"pricing/term\" AS pricing_term, \"pricing/unit\" AS pricing_unit, TRY_CAST(\"reservation/effectivecost\" AS DOUBLE) AS reservation_effective_cost, TRY_CAST(\"savingsplan/savingsplaneffectivecost\" AS DOUBLE) AS savings_plan_savings_plan_effective_cost FROM ${aws_glue_catalog_database.cur_database.name}.${replace(each.key, "-", "_")}" \
        --work-group "${aws_athena_workgroup.cur_analysis.name}" \
        --region "${data.aws_region.current.name}" \
        --output text
    EOF
  }

  depends_on = [aws_glue_catalog_table.cur_table]
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
