terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
# Credentials come from the "teracloud" AWS CLI profile (~/.aws/credentials)
provider "aws" {
  region  = "us-east-1"
  profile = "teracloud"
}
