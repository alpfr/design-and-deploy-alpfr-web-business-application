terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# CloudFront certificates must live in us-east-1, so everything is created there.
provider "aws" {
  region = "us-east-1"
}
