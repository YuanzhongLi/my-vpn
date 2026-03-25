module "vpc" {
  source = "../modules/aws/vpc"
  env    = local.env
}

module "subnet" {
  source = "../modules/aws/subnet"
  env    = local.env
  vpc_id = module.vpc.id
}

module "internet_gateway" {
  source = "../modules/aws/internet_gateway"
  env    = local.env
  vpc_id = module.vpc.id
}

module "route_table" {
  source              = "../modules/aws/route_table"
  env                 = local.env
  vpc_id              = module.vpc.id
  internet_gateway_id = module.internet_gateway.id
  public_subnet_ids   = local.public_subnet_ids
}

module "security_group" {
  source = "../modules/aws/security_group"
  env    = local.env
  vpc_id = module.vpc.id
}

module "iam_role" {
  source     = "../modules/aws/iam_role"
  env        = local.env
  region     = local.region
  account_id = local.account_id
}

module "ec2" {
  source                    = "../modules/aws/ec2"
  env                       = local.env
  subnet_id                 = module.subnet.id_public_1a
  security_group_id         = module.security_group.id_vpn
  iam_instance_profile_name = module.iam_role.instance_profile_name_vpn
}

