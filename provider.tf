terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "teracloud-terraform-state"
    key          = "vpc/terraform.tfstate"
    region       = "us-east-1"
    profile      = "teracloud"
    use_lockfile = true
  }
}

# Configure the AWS Provider
# Credentials come from the "teracloud" AWS CLI profile (~/.aws/credentials)
provider "aws" {
  region  = "us-east-1"
  profile = "teracloud"
}
