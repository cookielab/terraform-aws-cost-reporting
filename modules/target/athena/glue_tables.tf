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

    # Full CUR columns (positional mapping via OpenCSVSerDe)
    # All 163 columns from a standard textORcsv CUR report with RESOURCES and SPLIT_COST_ALLOCATION_DATA.
    # OpenCSVSerDe maps by position, so order must match the CSV header exactly.

    # identity (1-2)
    columns {
      name = "identity/lineitemid"
      type = "string"
    }
    columns {
      name = "identity/timeinterval"
      type = "string"
    }

    # bill (3-9)
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

    # lineItem (10-29)
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

    # product (30-127)
    columns {
      name = "product/productname"
      type = "string"
    }
    columns {
      name = "product/sizeflex"
      type = "string"
    }
    columns {
      name = "product/alarmtype"
      type = "string"
    }
    columns {
      name = "product/availability"
      type = "string"
    }
    columns {
      name = "product/availabilityzone"
      type = "string"
    }
    columns {
      name = "product/cacheengine"
      type = "string"
    }
    columns {
      name = "product/capacitystatus"
      type = "string"
    }
    columns {
      name = "product/classicnetworkingsupport"
      type = "string"
    }
    columns {
      name = "product/clockspeed"
      type = "string"
    }
    columns {
      name = "product/contenttype"
      type = "string"
    }
    columns {
      name = "product/currentgeneration"
      type = "string"
    }
    columns {
      name = "product/databaseedition"
      type = "string"
    }
    columns {
      name = "product/databaseengine"
      type = "string"
    }
    columns {
      name = "product/dedicatedebsthroughput"
      type = "string"
    }
    columns {
      name = "product/dedicatedebsthroughputdescription"
      type = "string"
    }
    columns {
      name = "product/deploymentoption"
      type = "string"
    }
    columns {
      name = "product/description"
      type = "string"
    }
    columns {
      name = "product/durability"
      type = "string"
    }
    columns {
      name = "product/ecu"
      type = "string"
    }
    columns {
      name = "product/endpointtype"
      type = "string"
    }
    columns {
      name = "product/enginecode"
      type = "string"
    }
    columns {
      name = "product/enhancednetworkingsupported"
      type = "string"
    }
    columns {
      name = "product/equivalentondemandsku"
      type = "string"
    }
    columns {
      name = "product/feecode"
      type = "string"
    }
    columns {
      name = "product/feedescription"
      type = "string"
    }
    columns {
      name = "product/fromlocation"
      type = "string"
    }
    columns {
      name = "product/fromlocationtype"
      type = "string"
    }
    columns {
      name = "product/fromregioncode"
      type = "string"
    }
    columns {
      name = "product/gpumemory"
      type = "string"
    }
    columns {
      name = "product/group"
      type = "string"
    }
    columns {
      name = "product/groupdescription"
      type = "string"
    }
    columns {
      name = "product/instancefamily"
      type = "string"
    }
    columns {
      name = "product/instancefamilycategory"
      type = "string"
    }
    columns {
      name = "product/instancetype"
      type = "string"
    }
    columns {
      name = "product/instancetypefamily"
      type = "string"
    }
    columns {
      name = "product/intelavx2available"
      type = "string"
    }
    columns {
      name = "product/intelavxavailable"
      type = "string"
    }
    columns {
      name = "product/intelturboavailable"
      type = "string"
    }
    columns {
      name = "product/licensemodel"
      type = "string"
    }
    columns {
      name = "product/location"
      type = "string"
    }
    columns {
      name = "product/locationtype"
      type = "string"
    }
    columns {
      name = "product/logsdestination"
      type = "string"
    }
    columns {
      name = "product/marketoption"
      type = "string"
    }
    columns {
      name = "product/maxiopsburstperformance"
      type = "string"
    }
    columns {
      name = "product/maxiopsvolume"
      type = "string"
    }
    columns {
      name = "product/maxthroughputvolume"
      type = "string"
    }
    columns {
      name = "product/maxvolumesize"
      type = "string"
    }
    columns {
      name = "product/memory"
      type = "string"
    }
    columns {
      name = "product/messagedeliveryfrequency"
      type = "string"
    }
    columns {
      name = "product/messagedeliveryorder"
      type = "string"
    }
    columns {
      name = "product/minvolumesize"
      type = "string"
    }
    columns {
      name = "product/minutestate"
      type = "string"
    }
    columns {
      name = "product/networkperformance"
      type = "string"
    }
    columns {
      name = "product/normalizationsizefactor"
      type = "string"
    }
    columns {
      name = "product/operatingsystem"
      type = "string"
    }
    columns {
      name = "product/operation"
      type = "string"
    }
    columns {
      name = "product/origin"
      type = "string"
    }
    columns {
      name = "product/overhead"
      type = "string"
    }
    columns {
      name = "product/physicalprocessor"
      type = "string"
    }
    columns {
      name = "product/preinstalledsw"
      type = "string"
    }
    columns {
      name = "product/processorarchitecture"
      type = "string"
    }
    columns {
      name = "product/processorfeatures"
      type = "string"
    }
    columns {
      name = "product/productfamily"
      type = "string"
    }
    columns {
      name = "product/queuetype"
      type = "string"
    }
    columns {
      name = "product/recipient"
      type = "string"
    }
    columns {
      name = "product/region"
      type = "string"
    }
    columns {
      name = "product/regioncode"
      type = "string"
    }
    columns {
      name = "product/requestdescription"
      type = "string"
    }
    columns {
      name = "product/requesttype"
      type = "string"
    }
    columns {
      name = "product/routingtarget"
      type = "string"
    }
    columns {
      name = "product/routingtype"
      type = "string"
    }
    columns {
      name = "product/servicecode"
      type = "string"
    }
    columns {
      name = "product/servicename"
      type = "string"
    }
    columns {
      name = "product/sku"
      type = "string"
    }
    columns {
      name = "product/steps"
      type = "string"
    }
    columns {
      name = "product/storage"
      type = "string"
    }
    columns {
      name = "product/storageclass"
      type = "string"
    }
    columns {
      name = "product/storagemedia"
      type = "string"
    }
    columns {
      name = "product/storagetype"
      type = "string"
    }
    columns {
      name = "product/tenancy"
      type = "string"
    }
    columns {
      name = "product/tier"
      type = "string"
    }
    columns {
      name = "product/tiertype"
      type = "string"
    }
    columns {
      name = "product/tolocation"
      type = "string"
    }
    columns {
      name = "product/tolocationtype"
      type = "string"
    }
    columns {
      name = "product/toregioncode"
      type = "string"
    }
    columns {
      name = "product/transcodingresult"
      type = "string"
    }
    columns {
      name = "product/transfertype"
      type = "string"
    }
    columns {
      name = "product/unbundledlicensing"
      type = "string"
    }
    columns {
      name = "product/usagetype"
      type = "string"
    }
    columns {
      name = "product/vcpu"
      type = "string"
    }
    columns {
      name = "product/version"
      type = "string"
    }
    columns {
      name = "product/videocodec"
      type = "string"
    }
    columns {
      name = "product/videoframerate"
      type = "string"
    }
    columns {
      name = "product/videoqualitysetting"
      type = "string"
    }
    columns {
      name = "product/videoresolution"
      type = "string"
    }
    columns {
      name = "product/volumeapiname"
      type = "string"
    }
    columns {
      name = "product/volumetype"
      type = "string"
    }
    columns {
      name = "product/vpcnetworkingsupport"
      type = "string"
    }

    # pricing (128-137)
    columns {
      name = "pricing/leasecontractlength"
      type = "string"
    }
    columns {
      name = "pricing/offeringclass"
      type = "string"
    }
    columns {
      name = "pricing/purchaseoption"
      type = "string"
    }
    columns {
      name = "pricing/ratecode"
      type = "string"
    }
    columns {
      name = "pricing/rateid"
      type = "string"
    }
    columns {
      name = "pricing/currency"
      type = "string"
    }
    columns {
      name = "pricing/publicondemandcost"
      type = "string"
    }
    columns {
      name = "pricing/publicondemandrate"
      type = "string"
    }
    columns {
      name = "pricing/term"
      type = "string"
    }
    columns {
      name = "pricing/unit"
      type = "string"
    }

    # reservation (138-156)
    columns {
      name = "reservation/amortizedupfrontcostforusage"
      type = "string"
    }
    columns {
      name = "reservation/amortizedupfrontfeeforbillingperiod"
      type = "string"
    }
    columns {
      name = "reservation/effectivecost"
      type = "string"
    }
    columns {
      name = "reservation/endtime"
      type = "string"
    }
    columns {
      name = "reservation/modificationstatus"
      type = "string"
    }
    columns {
      name = "reservation/normalizedunitsperreservation"
      type = "string"
    }
    columns {
      name = "reservation/numberofreservations"
      type = "string"
    }
    columns {
      name = "reservation/recurringfeeforusage"
      type = "string"
    }
    columns {
      name = "reservation/reservationarn"
      type = "string"
    }
    columns {
      name = "reservation/starttime"
      type = "string"
    }
    columns {
      name = "reservation/subscriptionid"
      type = "string"
    }
    columns {
      name = "reservation/totalreservednormalizedunits"
      type = "string"
    }
    columns {
      name = "reservation/totalreservedunits"
      type = "string"
    }
    columns {
      name = "reservation/unitsperreservation"
      type = "string"
    }
    columns {
      name = "reservation/unusedamortizedupfrontfeeforbillingperiod"
      type = "string"
    }
    columns {
      name = "reservation/unusednormalizedunitquantity"
      type = "string"
    }
    columns {
      name = "reservation/unusedquantity"
      type = "string"
    }
    columns {
      name = "reservation/unusedrecurringfee"
      type = "string"
    }
    columns {
      name = "reservation/upfrontvalue"
      type = "string"
    }

    # savingsPlan (157-163)
    columns {
      name = "savingsplan/totalcommitmenttodate"
      type = "string"
    }
    columns {
      name = "savingsplan/savingsplanarn"
      type = "string"
    }
    columns {
      name = "savingsplan/savingsplanrate"
      type = "string"
    }
    columns {
      name = "savingsplan/usedcommitment"
      type = "string"
    }
    columns {
      name = "savingsplan/savingsplaneffectivecost"
      type = "string"
    }
    columns {
      name = "savingsplan/amortizedupfrontcommitmentforbillingperiod"
      type = "string"
    }
    columns {
      name = "savingsplan/recurringcommitmentforbillingperiod"
      type = "string"
    }
  }

  partition_keys {
    name = "billing_period"
    type = "string"
  }
}
