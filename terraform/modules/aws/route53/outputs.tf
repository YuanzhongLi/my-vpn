output "zone_id_vpn" {
  value = aws_route53_zone.vpn.zone_id
}

output "name_servers_vpn" {
  value = aws_route53_zone.vpn.name_servers
}
