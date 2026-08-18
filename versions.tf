terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  required_version = ">= 1.10"
  backend "s3" {
    bucket       = "tf-state-workshop-lm-104981180500"
    key          = "tf-workshop/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
