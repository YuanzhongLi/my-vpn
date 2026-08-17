variable "subdomain" {
  type = string
}

data "aws_caller_identity" "current" {}

locals {
  env        = "prd"
  account_id = data.aws_caller_identity.current.account_id
  region     = "ap-northeast-1"
  project    = "my-vpn"

  public_subnet_ids = [
    module.subnet.id_public_1a,
  ]
}
