terraform {
  backend "s3" {
    bucket  = "my-vpn-terraform-prd"
    key     = "main.tfstate"
    region  = "ap-northeast-1"
    encrypt = true
    profile = "my-vpn-terraform-prd"
  }
}
