# Account-specific terraform configuration
provider "aws" {
  # Sandbox in us-east-1
  region  = "us-east-1"
  profile = "terraform-sandbox"
  default_tags {
    tags = {
      Provisioner = "Terraform"
      Repository = "gopherbot-ram"
    }
  }
}

# Local definition; each piece of infrastructure has it's own
# s3 key.
terraform {
  backend "s3" {
    bucket  = "welld-sandbox-terraform-state"
    key     = "gopherbot-ram/state"
    region  = "us-east-1"
    profile = "terraform-sandbox"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  required_version = ">= 1.3.0"
}