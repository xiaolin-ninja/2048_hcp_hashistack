# VPC #


variable "region" {
  type        = string
  default     = "us-east-1"
}

variable "name" {
  type    = string
  default = "xx-2048-hashistack"
}

variable "public_subnets" {
  type = list(any)
  default = [
    "10.0.20.0/24",
    "10.0.21.0/24",
    "10.0.22.0/24",
  ]
}
variable "cidr" {
  default = "10.0.0.0/16"
}

# Compute 

variable "ami_id" {
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "What to name the Nomad cluster and all of its associated resources"
  type        = string
  default     = "hcp-2048"
}

variable "cluster_tag_key" {
  description = "The tag the EC2 Instances will look for to automatically discover each other and form a cluster."
  type        = string
  default     = "xx-2048-servers"
}

variable "ssh_key_name" {
  description = "The name of an EC2 Key Pair that can be used to SSH to the EC2 Instances in this cluster. Set to an empty string to not associate a Key Pair."
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "The ID of the VPC in which the nodes will be deployed.  Uses default VPC if not supplied."
  type        = string
  default     = null
}

variable "spot_price" {
  description = "The maximum hourly price to pay for EC2 Spot Instances."
  type        = number
  default     = null
}

variable "public_subnet" {
  description = "The ID of the public subnet in which the runtime cluster will be deployed"
  default = "subnet-0b63522bd122d750a"
}

variable "nomad_datacenter" {
  type        = string
  description = "Nomad Datacenter"
  default     = "xx-2048"
}
