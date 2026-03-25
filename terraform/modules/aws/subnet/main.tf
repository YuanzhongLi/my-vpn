resource "aws_subnet" "public_1a" {
  vpc_id                  = var.vpc_id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = "ap-northeast-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "my-vpn-public-subnet-1a-${var.env}"
  }
}
