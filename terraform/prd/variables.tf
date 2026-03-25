locals {
  env        = "prd"
  account_id = "<AWS_ACCOUNT_ID>"
  region     = "ap-northeast-1"
  project    = "my-vpn"

  public_subnet_ids = [
    module.subnet.id_public_1a,
  ]
}
