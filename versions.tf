terraform {
  required_version = "~>1.4.5"
  required_providers {
    aws = {
      source  = "registry.terraform.io/hashicorp/aws"
      version = ">= 3.73.0"
    }

    vault = {
      source  = "registry.terraform.io/hashicorp/vault"
      version = ">= 3.14.0"
    }

    hcp = {
      source  = "registry.terraform.io/hashicorp/hcp"
      version = ">= 0.56.0"
    }

    http = {
      source  = "registry.terraform.io/hashicorp/http"
      version = ">= 3.2.1"
    }
  }
}