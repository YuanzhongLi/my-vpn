data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "vpn" {
  ami                    = data.aws_ssm_parameter.al2023_ami.value
  instance_type          = "t3.nano"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.iam_instance_profile_name

  user_data                   = file("${path.module}/user_data.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
  }

  tags = {
    Name = "my-vpn-ec2-vpn-${var.env}"
  }
}
