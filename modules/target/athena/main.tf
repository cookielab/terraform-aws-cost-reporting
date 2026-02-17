data "aws_caller_identity" "current" {}

locals {
  # Filter accounts that need column fix views
  accounts_needing_fix = {
    for key, value in var.source_accounts :
    key => value
    if contains(var.accounts_with_misaligned_columns, key)
  }
}
