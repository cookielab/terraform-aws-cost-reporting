variable "cur_bucket_id" {
  description = "ID of the CUR reports S3 bucket"
  type        = string
}

variable "cur_bucket_arn" {
  description = "ARN of the CUR reports S3 bucket"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names (e.g., bucket name)"
  type        = string
}

variable "create_reader_role" {
  description = "Create IAM role for read-only CUR access (for AssumeRole)"
  type        = bool
  default     = true
}

variable "require_mfa_for_reader_role" {
  description = "Require MFA for assuming the CUR reader role (security best practice)"
  type        = bool
  default     = true
}

variable "create_reader_user" {
  description = "Create IAM user with access keys for read-only access (e.g., for Grafana, ClickHouse)"
  type        = bool
  default     = false
}

variable "enable_athena_access" {
  description = "Include Athena/Glue permissions in reader policies"
  type        = bool
  default     = false
}

variable "glue_database_name" {
  description = "Name of the Glue database (required if enable_athena_access=true)"
  type        = string
  default     = ""
}

variable "athena_workgroup_name" {
  description = "Name of the Athena workgroup (required if enable_athena_access=true)"
  type        = string
  default     = ""
}

variable "athena_results_bucket_arn" {
  description = "ARN of the Athena results bucket (required if enable_athena_access=true)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
