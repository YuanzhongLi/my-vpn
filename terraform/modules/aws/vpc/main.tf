resource "aws_vpc" "this" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "my-vpn-vpc-${var.env}"
  }
}
