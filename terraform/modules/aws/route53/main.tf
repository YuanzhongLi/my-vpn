resource "aws_route53_zone" "vpn" {
  name = var.subdomain

  tags = {
    Name = "my-vpn-zone-vpn-${var.env}"
  }
}
