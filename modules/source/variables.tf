# -----------------------------------------------------------------------------
# Resource Creation Toggles
# -----------------------------------------------------------------------------

variable "create_bucket" {
  description = "Whether to create a new S3 bucket or use an existing one. When false, s3_bucket_name is required."
  type        = bool
  default     = true
}

variable "create_report" {
  description = "Whether to create a new CUR report definition. Set to false if the account already has a CUR report configured."
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Lambda / Target Account
# -----------------------------------------------------------------------------

variable "lambda_function_arn" {
  description = "ARN of the Lambda function in the target account that will process CUR reports. Required when use_sns = false."
  type        = string
  default     = ""
}

variable "lambda_function_role_arn" {
  description = "ARN of the IAM role for the Lambda function (for bucket policy)"
  type        = string
}

# -----------------------------------------------------------------------------
# SNS Configuration
# -----------------------------------------------------------------------------

variable "use_sns" {
  description = "Use SNS topic for S3 event notifications instead of direct Lambda invocation. When true, creates an SNS topic that the target Lambda can subscribe to."
  type        = bool
  default     = false
}

variable "sns_topic_name" {
  description = "Name of the SNS topic for CUR notifications. Defaults to cur-notifications-{account_id}."
  type        = string
  default     = null
}

variable "sns_subscriber_arns" {
  description = "List of ARNs (Lambda functions or SQS queues) allowed to subscribe to the SNS topic."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# S3 Bucket Configuration
# -----------------------------------------------------------------------------

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for CUR reports. If not provided, defaults to cur-csv-{account_id}"
  type        = string
  default     = null
}

variable "s3_bucket_lifecycle" {
  description = "S3 bucket lifecycle configuration. Only used when create_bucket = true."
  type = object({
    transition_to_ia_days      = number
    transition_to_glacier_days = number
  })
  default = {
    transition_to_ia_days      = 90
    transition_to_glacier_days = 180
  }
}

# -----------------------------------------------------------------------------
# CUR Report Configuration
# -----------------------------------------------------------------------------

variable "cur_time_unit" {
  description = "Time unit for CUR report (HOURLY or DAILY)"
  type        = string
  default     = "HOURLY"
}

variable "cur_format" {
  description = "Format for CUR report"
  type        = string
  default     = "textORcsv"
  validation {
    condition     = contains(["textORcsv", "Parquet"], var.cur_format)
    error_message = "Format must be either 'textORcsv' or 'Parquet'."
  }
}

variable "cur_compression" {
  description = "Compression format for CUR report"
  type        = string
  default     = "GZIP"
  validation {
    condition     = contains(["GZIP", "ZIP", "Parquet"], var.cur_compression)
    error_message = "Compression must be either 'GZIP', 'ZIP', or 'Parquet'."
  }
}

variable "cur_s3_prefix" {
  description = "S3 prefix for CUR reports. Only used when create_report = false to configure S3 notifications on an existing report."
  type        = string
  default     = "cur-reports"
}

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
