terraform {
  required_version = "~> 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "ap-northeast-1"
  profile = "my-vpn-terraform-prd"

  default_tags {
    tags = {
      Env     = "prd"
      Project = "my-vpn"
    }
  }
}
