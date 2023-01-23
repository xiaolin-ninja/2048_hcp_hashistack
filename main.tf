# Variables

variable "id" {
  type    = string
  default = "xx-2048"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

# HCP

resource "hcp_hvn" "xx-2048-hvn" {
  hvn_id = var.id
  cloud_provider = "aws"
  region = "us-east-1"
}

provider "aws" {
  region = var.region
}

provider "hcp" {
}

resource "aws_vpc" "peer" {
  cidr_block = "172.31.0.0/16"
}

data "aws_arn" "peer" {
  arn = aws_vpc.peer.arn
}

resource "hcp_aws_network_peering" "peer" {
  hvn_id              = hcp_hvn.xx-2048-hvn.hvn_id
  peering_id          = var.id
  peer_vpc_id         = aws_vpc.peer.id
  peer_account_id     = aws_vpc.peer.owner_id
  peer_vpc_region     = data.aws_arn.peer.region
}

resource "hcp_hvn_route" "peer_route" {
  hvn_link         = hcp_hvn.xx-2048-hvn.self_link
  hvn_route_id     = var.id
  destination_cidr = aws_vpc.peer.cidr_block
  target_link      = hcp_aws_network_peering.peer.self_link
}

resource "aws_vpc_peering_connection_accepter" "peer" {
  vpc_peering_connection_id = hcp_aws_network_peering.peer.provider_peering_id
  auto_accept               = true
}

# Consul

resource "hcp_consul_cluster" "xx-2048-consul" {
  hvn_id = hcp_hvn.xx-2048-hvn.hvn_id
  cluster_id = var.id
  tier = "development"
}

# Vault

provider "vault" {
  address = hcp_vault_cluster.xx-2048-vault.vault_public_endpoint_url
  namespace = "admin"
  token = hcp_vault_cluster.xx-2048-vault-token.token
}

resource "hcp_vault_cluster" "xx-2048-vault" {
  hvn_id = hcp_hvn.xx-2048-hvn.hvn_id
  cluster_id = var.id
}

resource "hcp_vault_cluster_admin_token" "xx-2048-vault-token" {
  cluster_id = hcp_vault_cluster.xx-2048-vault.cluster_id
}

