# =============================================================================
# Athena Workgroup
# =============================================================================

resource "aws_athena_workgroup" "cur_analysis" {
  name        = "cur-analysis"
  description = "Workgroup for AWS Cost and Usage Reports analysis"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${module.athena_results_bucket.s3_bucket_id}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = merge(var.tags, {
    Name      = "CUR Analysis Workgroup"
    Purpose   = "Athena workgroup for CUR queries"
    ManagedBy = "Terraform"
  })
}
