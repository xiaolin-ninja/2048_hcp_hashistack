data "aws_ami" "base" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "name"
    values = ["ubuntu/images/*ubuntu-jammy-22.04-amd64-server-*"]
  }
}


#---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE SERVER NODES
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_security_group" "xx_2048" {
  name   = "2048 Hashistack Use Case"
  vpc_id = module.vpc.vpc_id
  ingress {
    description      = "Allow All"
    from_port        = 0
    to_port          = 0
    protocol         = "all"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    description      = "Allow All"
    from_port        = 0
    to_port          = 0
    protocol         = "all"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "2048 Hashistack Use Case"
  }
}

resource "aws_launch_template" "nomad-servers" {
  name = "XX_2048_Nomad_Servers"

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size = 16
    }
  }

  image_id = data.aws_ami.base.image_id

  instance_initiated_shutdown_behavior = "terminate"

  instance_type = "t3.medium"
  iam_instance_profile {
    arn = aws_iam_instance_profile.nomad_server.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = true
  }

  vpc_security_group_ids = [aws_security_group.xx_2048.id]

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "Nomad-server"
    }
  }

  user_data = base64encode(templatefile("user-data-server.sh", {
    nomad_region       = var.region,
    nomad_datacenter   = var.cluster_name,
    consul_config_file = base64decode(hcp_consul_cluster.xx_2048_consul.consul_config_file),
    consul_ca_file     = base64decode(hcp_consul_cluster.xx_2048_consul.consul_ca_file),
    consul_acl_token   = hcp_consul_cluster.xx_2048_consul.consul_root_token_secret_id,
    vault_endpoint     = hcp_vault_cluster.xx_2048_vault.vault_private_endpoint_url,
    aws_role           = vault_aws_auth_backend_role.nomad_server.role
  }))

}

resource "aws_autoscaling_group" "nomad-servers" {
  name                = "2048 Hashistack servers"
  vpc_zone_identifier = module.vpc.public_subnets

  desired_capacity = 1
  max_size         = 3
  min_size         = 1

  launch_template {
    id      = aws_launch_template.nomad-servers.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.nomad-servers.arn]
}

resource "aws_lb_target_group" "nomad-servers" {
  name     = "nomad-servers"
  port     = 4646
  protocol = "TCP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    port     = 4646
    protocol = "TCP"
  }
}

data "aws_subnets" "subnet_ids" {
  filter {
    name   = "vpc-id"
    values = [module.vpc.vpc_id]
  }

  tags = {
    Name = "${var.name}-public"
  }
  depends_on = [
    module.vpc
  ]
}


resource "aws_lb" "nomad-servers" {
  name = "nomad-servers"

  internal           = false
  load_balancer_type = "network"
  subnets            = [for subnet in data.aws_subnets.subnet_ids.ids : subnet]



  depends_on = [aws_lb_target_group.nomad-servers]
}

resource "aws_lb_listener" "nomad-servers" {
  load_balancer_arn = aws_lb.nomad-servers.id
  port              = 4646
  protocol          = "TCP"

  default_action {
    target_group_arn = aws_lb_target_group.nomad-servers.id
    type             = "forward"
  }
}


output "nomad_servers_http" {
  value = "https://${aws_lb.nomad-servers.dns_name}:4646"
}
#------------------------



resource "aws_launch_template" "nomad-clients" {
  name = "XX_2048_Nomad_Clients"

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size = 16
    }
  }

  image_id = data.aws_ami.base.image_id

  instance_initiated_shutdown_behavior = "terminate"

  instance_type = "t3.medium"
  iam_instance_profile {
    arn = aws_iam_instance_profile.nomad_client.arn
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "enabled"
  }

  monitoring {
    enabled = true
  }

  vpc_security_group_ids = [aws_security_group.xx_2048.id]

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "Nomad-Client"
    }
  }

  user_data = base64encode(templatefile("user-data-client.sh", {
    nomad_region       = var.region,
    nomad_datacenter   = var.cluster_name,
    consul_config_file = base64decode(hcp_consul_cluster.xx_2048_consul.consul_config_file),
    consul_ca_file     = base64decode(hcp_consul_cluster.xx_2048_consul.consul_ca_file),
    consul_acl_token   = hcp_consul_cluster.xx_2048_consul.consul_root_token_secret_id,
    vault_endpoint     = hcp_vault_cluster.xx_2048_vault.vault_private_endpoint_url,
    aws_role           = vault_aws_auth_backend_role.nomad_client.role
  }))

}

resource "aws_autoscaling_group" "nomad-clients" {
  name                = "2048 Hashistack Clients"
  vpc_zone_identifier = module.vpc.public_subnets

  desired_capacity = 1
  max_size         = 3
  min_size         = 1

  launch_template {
    id      = aws_launch_template.nomad-clients.id
    version = "$Latest"
  }
}
