# =============================================================================
# Glue Catalog Database
# =============================================================================

resource "aws_glue_catalog_database" "cur_database" {
  name        = "cur_database"
  description = "Database for AWS Cost and Usage Reports from all source accounts"

  tags = merge(var.tags, {
    Name      = "CUR Database"
    Purpose   = "Cost and Usage Reports metadata"
    ManagedBy = "Terraform"
  })
}
