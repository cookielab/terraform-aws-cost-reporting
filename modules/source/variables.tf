variable "lambda_function_arn" {
  description = "ARN of the Lambda function in the target account that will process CUR reports"
  type        = string
}

variable "lambda_function_role_arn" {
  description = "ARN of the IAM role for the Lambda function (for bucket policy)"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket for CUR reports. If not provided, defaults to cur-csv-{account_id}"
  type        = string
  default     = null
}

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

variable "s3_bucket_lifecycle" {
  description = "S3 bucket lifecycle configuration"
  type = object({
    transition_to_ia_days      = number
    transition_to_glacier_days = number
  })
  default = {
    transition_to_ia_days      = 90
    transition_to_glacier_days = 180
  }
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
