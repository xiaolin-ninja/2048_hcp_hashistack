provider "aws" {
  region = var.region
}

module "vpc" {
  source         = "terraform-aws-modules/vpc/aws"
  version        = "4.0.1"
  name           = var.name
  cidr           = var.cidr
  public_subnets = var.public_subnets
  public_subnet_tags = {
    Name = "${var.name}-public"
  }
  map_public_ip_on_launch = true

  azs                                           = slice(data.aws_availability_zones.available.*.names[0], 0, 3)
  enable_dns_hostnames                          = true
  enable_ipv6                                   = true
  public_subnet_assign_ipv6_address_on_creation = true
  public_subnet_ipv6_prefixes                   = [0, 1, 2]

  tags = {
    Terraform = "true"
    Name      = var.name
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}
