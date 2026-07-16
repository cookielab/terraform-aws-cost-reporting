terraform {
  required_version = ">= 1.5, < 2.0"

  required_providers {
    # >= 6.0 for data.aws_region.region; the older `.name` attribute is deprecated.
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
