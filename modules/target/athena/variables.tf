variable "cur_bucket_id" {
  description = "ID of the CUR reports S3 bucket"
  type        = string
}

variable "cur_bucket_arn" {
  description = "ARN of the CUR reports S3 bucket"
  type        = string
}

variable "source_accounts" {
  description = <<-EOT
    Map of source account configurations for Athena/Glue crawlers.
    Key is the source account identifier (used for table naming).
    Required: destination_prefix (path in CUR bucket where reports are stored)
  EOT
  type = map(object({
    account_id         = string
    destination_prefix = string
  }))
}

variable "accounts_with_misaligned_columns" {
  description = <<-EOT
    Set of source account keys that have misaligned columns due to OpenCSVSerDe bug.
    This occurs when the invoicing entity contains a comma (e.g., "Amazon Web Services, Inc.")
    which causes column shifting in CSV parsing.
  EOT
  type        = set(string)
  default     = []
}

variable "athena_results_bucket_name" {
  description = "Name for the Athena query results bucket"
  type        = string
}

variable "athena_query_results_retention_days" {
  description = "Days to retain Athena query results (these are temporary query outputs, not the CUR data)"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
