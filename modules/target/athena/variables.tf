variable "cur_bucket_id" {
  description = "ID of the CUR reports S3 bucket"
  type        = string
}

variable "cur_bucket_arn" {
  description = "ARN of the CUR reports S3 bucket"
  type        = string
}

variable "glue_database_name" {
  description = "Name of the Glue database for CUR 2.0 data"
  type        = string
  default     = "cur2_database"
}

variable "data_export_prefix" {
  description = "S3 prefix under the CUR bucket where Data Exports are delivered (the crawler scans this path)"
  type        = string
  default     = "cur2/"
}

variable "crawler_schedule" {
  description = "Cron expression for the Glue crawler schedule (discovers partitions and reconciles schema)"
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "account_map" {
  description = <<-EOT
    Optional account ID to name/client mapping, uploaded as a CSV and exposed as
    the `account_map` Glue table for joins. Empty = do not manage the account map.
    In practice you only fill account_id and account_name; the rest have defaults.
  EOT
  type = list(object({
    account_id       = string
    account_name     = string
    client_id        = optional(string, "")
    client_name      = optional(string, "")
    payer_account_id = optional(string)
    is_org_member    = optional(bool, true)
    environment      = optional(string, "production")
    active           = optional(bool, true)
  }))
  default = []
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
