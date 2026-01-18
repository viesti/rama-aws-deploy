
###
# variables & configuration
###

## Required vars

variable "region" { type = string }

variable "cluster_name" { type = string } # from rama-cluster.sh
variable "key_name" { type = string }     # from ~/.rama/auth.tfvars

# From rama.tfvars
variable "username" { type = string }
variable "vpc_security_group_ids" { type = list(string) }

variable "rama_source_path" { type = string }
variable "license_source_path" {
  type    = string
  default = ""
}
variable "zookeeper_url" { type = string }

variable "ami_id" { type = string }

variable "instance_type" { type = string }

variable "volume_size_gb" {
  type    = number
  default = 100
}

variable "use_private_ip" {
  type    = bool
  default = false
}

variable "private_ssh_key" {
  type    = string
  default = null
}

provider "aws" {
  region      = var.region
  max_retries = 25
  version     = "~> 4.1.0"
}

provider "cloudinit" {
  version = "~> 2.2.0"
}

locals {
  home_dir = "/home/${var.username}"
  systemd_dir = "/etc/systemd/system"
  vpc_security_group_ids = var.vpc_security_group_ids
}

###
# VPC
###

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

###
# Create EC2 instance
###

resource "aws_instance" "rama" {
  ami           = var.ami_id
  instance_type = var.instance_type
  # subnet_id              = local.subnet_id
  vpc_security_group_ids = local.vpc_security_group_ids
  key_name               = var.key_name

  user_data = data.cloudinit_config.rama_config.rendered

  tags = {
    Name = "${terraform.workspace}-rama"
  }

  root_block_device {
    volume_size = var.volume_size_gb
  }
}

data "cloudinit_config" "rama_config" {
  part {
    content_type = "text/x-shellscript"
    content = templatefile("../common/setup-disks.sh", {
      username = var.username
    })
  }
}

###
# Setup local to allow `rama-my-cluster` commands
###
resource "null_resource" "local" {
  # Render to local file on machine
  # https://github.com/hashicorp/terraform/issues/8090#issuecomment-291823613
  provisioner "local-exec" {
    command = format(
      "cat <<\"EOF\" > \"%s\"\n%s\nEOF",
      "/tmp/deployment.yaml",
      templatefile("../common/local.yaml", {
        zk_public_ip         = aws_instance.rama.public_ip
        zk_private_ip        = aws_instance.rama.private_ip
        conductor_public_ip  = aws_instance.rama.public_ip
        conductor_private_ip = aws_instance.rama.private_ip
      })
      )
  }
}

###
# Output useful info
###
output "rama_ip" {
  value = var.use_private_ip ? aws_instance.rama.private_ip : aws_instance.rama.public_ip
}

output "conductor_ui" {
  value = "http://${var.use_private_ip ? aws_instance.rama.private_ip : aws_instance.rama.public_ip}:8888"
}

output "ec2_console" {
  value = "https://us-west-2.console.aws.amazon.com/ec2/v2/home?region=us-west-2#Instances:tag:Name=${var.cluster_name}-cluster-supervisor,${var.cluster_name}-cluster-conductor,${var.cluster_name}-cluster-zookeeper;instanceState=running;sort=desc:tag:Name"
}

###
# Outputs for Ansible inventory generation
###
output "rama_user" {
  value = var.username
}

output "private_ssh_key" {
  value = var.private_ssh_key
}
