terraform {
  required_version = "1.14.3"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.28.0"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
      version = "2.3.7"
    }
  }
}

provider "aws" {
  max_retries = 25
}
