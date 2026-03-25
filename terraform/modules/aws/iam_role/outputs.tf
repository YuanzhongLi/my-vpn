output "arn_vpn" {
  value = aws_iam_role.vpn.arn
}

output "instance_profile_name_vpn" {
  value = aws_iam_instance_profile.vpn.name
}
