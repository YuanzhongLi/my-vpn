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

