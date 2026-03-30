output "ec2_vpn_id" {
  value = module.ec2.id_vpn
}

output "route53_vpn_name_servers" {
  value = module.route53.name_servers_vpn
}

output "route53_vpn_zone_id" {
  value = module.route53.zone_id_vpn
}

output "subdomain" {
  value = var.subdomain
}
