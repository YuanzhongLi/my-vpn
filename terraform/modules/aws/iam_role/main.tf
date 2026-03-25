data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpn" {
  name               = "my-vpn-role-vpn-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "my-vpn-role-vpn-${var.env}"
  }
}

data "aws_iam_policy_document" "vpn" {
  statement {
    sid = "SSMParameterStoreRead"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = [
      "arn:aws:ssm:${var.region}:${var.account_id}:parameter/vpn/*",
    ]
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "vpn" {
  name   = "my-vpn-policy-vpn-${var.env}"
  role   = aws_iam_role.vpn.id
  policy = data.aws_iam_policy_document.vpn.json
}

resource "aws_iam_instance_profile" "vpn" {
  name = "my-vpn-profile-vpn-${var.env}"
  role = aws_iam_role.vpn.name

  tags = {
    Name = "my-vpn-profile-vpn-${var.env}"
  }
}
