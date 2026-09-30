terraform {
  required_version = ">= 1.7" # mock_provider in `terraform test`

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = { project = "decide-in-code" }
  }
}
