# =============================================================================
# Athena Query Results Bucket
# =============================================================================

module "athena_results_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "3.15.2"

  bucket = var.athena_results_bucket_name

  versioning = {
    enabled = true
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # Query results are temporary - safe to expire
  lifecycle_rule = [
    {
      id     = "cleanup_old_results"
      status = "Enabled"

      filter = {
        prefix = ""
      }

      expiration = {
        days = var.athena_query_results_retention_days
      }

      abort_incomplete_multipart_upload_days = 7
    },
    {
      id     = "expire_old_versions"
      status = "Enabled"

      filter = {
        prefix = ""
      }

      noncurrent_version_expiration = {
        noncurrent_days = 7
      }
    }
  ]

  tags = merge(var.tags, {
    Name      = "Athena Query Results"
    Purpose   = "Store Athena query results for CUR analysis"
    ManagedBy = "Terraform"
  })
}
