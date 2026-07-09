# =============================================================================
# CUR 2.0 Source Module - BCM Data Exports Export
# =============================================================================
# Creates a CUR 2.0 export that writes Parquet reports straight into the central
# bucket, cross-account. The write is authorized entirely by that bucket's
# policy (see the target module) - nothing else is needed on the source side.
#
# Managed via aws_cloudcontrolapi_resource rather than aws_bcmdataexports_export:
# the native resource cannot set S3BucketOwner, which BCM Data Exports requires
# for cross-account delivery. Without it CreateExport fails with
# "ValidationException: S3 bucket permission validation failed".
# See terraform-provider-aws issue #47613 / PR #47958 (both still open).
# The AWS::BCMDataExports::Export CloudFormation schema behind Cloud Control
# does expose S3BucketOwner, which is also how the CID template does it.
#
# The target module's bucket policy must exist before this runs: Data Exports
# validates S3 write permissions at export creation time.
# =============================================================================

data "aws_caller_identity" "current" {
  provider = aws.us_east_1
}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Delivered path: <bucket>/cur2/<account_id>/<export_name>/data/BILLING_PERIOD=YYYY-MM/
  s3_prefix = coalesce(var.s3_prefix, "cur2/${local.account_id}")

  # Canonical column catalogue. The target module's Athena submodule carries an
  # identical copy; CI asserts the two stay byte-for-byte equal. It is duplicated
  # rather than shared because neither sharing mechanism survives a plain local
  # module path: "${path.module}/../.." escapes into .terraform/ (Terraform
  # symlinks local modules), and a "../columns" module source is rejected with
  # "Local module path escapes module package".
  catalogue = jsondecode(file("${path.module}/cur2_columns.json"))

  # BCM Data Exports rejects "SELECT *" - columns must always be enumerated.
  # This is an AWS-side limitation, not a Terraform one (provider issue #37860
  # was closed because the AWS CLI rejects it too). A column group may only be
  # selected when its INCLUDE_* flag is TRUE, otherwise CreateExport fails with
  # "Columns are not a subset of table" - so the same variables drive both.
  query_columns = concat(
    local.catalogue.query_columns.base,
    var.enable_split_cost_allocation_data ? local.catalogue.query_columns.include_split_cost_allocation_data : [],
    var.enable_iam_principal_data ? local.catalogue.query_columns.include_iam_principal_data : [],
  )
  query_statement = "SELECT ${join(", ", local.query_columns)} FROM COST_AND_USAGE_REPORT"

  # INCLUDE_RESOURCES is fixed TRUE, as in the CID template: the catalogue's base
  # column set already assumes line_item_resource_id and resource_tags exist.
  table_configuration = merge(
    {
      TIME_GRANULARITY                      = var.time_granularity
      INCLUDE_RESOURCES                     = "TRUE"
      INCLUDE_MANUAL_DISCOUNT_COMPATIBILITY = "FALSE"
      INCLUDE_SPLIT_COST_ALLOCATION_DATA    = var.enable_split_cost_allocation_data ? "TRUE" : "FALSE"
      INCLUDE_IAM_PRINCIPAL_DATA            = var.enable_iam_principal_data ? "TRUE" : "FALSE"
    },
    var.billing_view_arn != null ? { BILLING_VIEW_ARN = var.billing_view_arn } : {},
  )

  s3_destination = merge(
    {
      S3Bucket = var.destination_bucket
      S3Prefix = local.s3_prefix
      S3Region = var.destination_region

      S3OutputConfigurations = {
        OutputType  = "CUSTOM"
        Overwrite   = var.overwrite
        Format      = "PARQUET"
        Compression = "PARQUET"
      }
    },
    var.destination_bucket_owner != null ? { S3BucketOwner = var.destination_bucket_owner } : {},
  )

  desired_state = jsonencode(merge(
    {
      Export = {
        Name        = var.export_name
        Description = var.description

        DataQuery = {
          QueryStatement      = local.query_statement
          TableConfigurations = { COST_AND_USAGE_REPORT = local.table_configuration }
        }

        DestinationConfigurations = {
          S3Destination = local.s3_destination
        }

        RefreshCadence = {
          Frequency = "SYNCHRONOUS"
        }
      }
    },
    length(var.tags) > 0 ? { Tags = [for k, v in var.tags : { Key = k, Value = v }] } : {},
  ))
}

resource "aws_cloudcontrolapi_resource" "cur2_export" {
  provider = aws.us_east_1

  type_name     = "AWS::BCMDataExports::Export"
  desired_state = local.desired_state
}
