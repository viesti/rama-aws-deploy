###
# VPC
###

module "vpc" {
  source       = "../../vpc"
  res_prefix   = var.cluster_name

  bastion_key_name = var.key_name
}

locals {
  zk_public_ips  = aws_instance.zookeeper[*].public_ip
  zk_private_ips = aws_instance.zookeeper[*].private_ip

  conductor_public_ip  = aws_instance.conductor.public_ip
  conductor_private_ip = aws_instance.conductor.private_ip

  home_dir    = "/home/${var.username}"
  systemd_dir = "/etc/systemd/system"

  # networking
  vpc_security_group_ids = [module.vpc.node_security_group_id]
  vpc_id                 = module.vpc.vpc_id
  subnet_id              = module.vpc.node_subnet_id
}

###
# Create EC2 instances
#
# These resources are defined to have no dependencies on other resouces. This
# way the EC2 instances can be created in parallel, which saves time.
###

resource "aws_instance" "zookeeper" {
  ami                    = var.zookeeper_ami_id
  instance_type          = var.zookeeper_instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = local.vpc_security_group_ids
  key_name               = var.key_name
  count                  = var.zookeeper_num_nodes

  tags = {
    Name = "${terraform.workspace}-cluster-zookeeper"
  }

  root_block_device {
    volume_size = 100
  }

  iam_instance_profile = module.vpc.node_instance_profile_name
}

# Conductor

data "cloudinit_config" "conductor_config" {
  part {
    content_type = "text/x-shellscript"
    content = templatefile("../common/setup-disks.sh", {
      username = var.username
    })
  }
}

resource "aws_instance" "conductor" {
  ami                    = var.conductor_ami_id
  instance_type          = var.conductor_instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = local.vpc_security_group_ids
  key_name               = var.key_name

  user_data_base64 = data.cloudinit_config.conductor_config.rendered

  iam_instance_profile = module.vpc.node_instance_profile_name

  tags = {
    Name = "${terraform.workspace}-cluster-conductor"
  }

  root_block_device {
    volume_size = 100
  }
}

# Supervisors

data "cloudinit_config" "supervisor_config" {
  part {
    content_type = "text/x-shellscript"
    content = templatefile("../common/setup-disks.sh", {
      username = var.username
    })
  }
}

resource "aws_instance" "supervisor" {
  ami                    = var.supervisor_ami_id
  count                  = var.supervisor_num_nodes
  instance_type          = var.supervisor_instance_type
  subnet_id              = local.subnet_id
  vpc_security_group_ids = local.vpc_security_group_ids
  key_name               = var.key_name

  user_data_base64 = data.cloudinit_config.supervisor_config.rendered

  iam_instance_profile = module.vpc.node_instance_profile_name

  tags = {
    Name = "${terraform.workspace}-cluster-supervisor"
  }

  root_block_device {
    volume_size = var.supervisor_volume_size_gb
  }
}

