variable "registry_username" {
  type = string
  default = ""
  env = ["REGISTRY_USERNAME"]
}

variable "registry_password" {
  type = string
  sensitive = true
  default = ""
  env = ["REGISTRY_PASSWORD"]
}

project = "2048-hashistack"

app "nomad" {
  build {
    use "docker" {}
    registry {
      use "docker" {
        image = "shxxu0212/wp-test"
        tag = "dev"
        local = false
        auth {
          username = var.registry_username
          password = var.registry_password
        }
      }
    }
  }

  deploy {
    use "nomad" {
      datacenter = "hcp-2048"
    }
  }
}


