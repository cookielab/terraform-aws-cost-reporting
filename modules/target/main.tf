# =============================================================================
# CUR 2.0 Target Module - Locals & Data
# =============================================================================

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  bucket_arn = "arn:aws:s3:::${var.bucket_name}"

  # The bucket-owning account produces its own CUR 2.0 export into this bucket
  # as well, so it is always authorized alongside the external source accounts.
  authorized_account_ids = distinct(concat(
    [data.aws_caller_identity.current.account_id],
    var.source_account_ids,
  ))

  # aws:SourceArn matchers for the CUR 2.0 (BCM Data Exports) service, one per
  # authorized account. Each account's export ARN embeds its own account ID, so
  # combining them with the SourceAccount list below is safe.
  source_arn_patterns = [
    for account_id in local.authorized_account_ids :
    "arn:aws:bcm-data-exports:${var.export_region}:${account_id}:export/*"
  ]
}
