# Account-specific terraform configuration
provider "aws" {
  # Sandbox in us-east-1
  region  = "us-east-1"
  default_tags {
    tags = {
      Provisioner = "Terraform"
      Repository = "floyd-gopherbot"
    }
  }
}

terraform {
  backend "local" {
    path = "floyd.tfstate"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }

  required_version = ">= 1.3.0"
}
