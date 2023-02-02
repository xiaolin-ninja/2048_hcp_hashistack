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

variable "aws_region" {
  type = string
  default = ""
  env = ["TF_VAR_region"]
}

project = "2048-hashistack"

pipeline "alb-deploy" {
  step "build" {
    use "build" {}
  }

  step "deploy" {
    use "deploy" {}
  }

  step "release" {
    use "release" {
    }
  }
}

app "nomad" {
#  runner {
#    profile = "nomad-runner"
#  }

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


