terraform {
  required_version = ">= 1.5, < 2.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # BCM Data Exports is a us-east-1 service. The export is managed through
      # the Cloud Control API rather than aws_bcmdataexports_export - see main.tf.
      version               = ">= 5.40"
      configuration_aliases = [aws.us_east_1]
    }
  }
}
