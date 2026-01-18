###
# Output useful info
###
output "zookeeper_ips" {
  value = var.use_private_ip ? local.zk_private_ips : local.zk_public_ips
}

output "conductor_ip" {
  value = var.use_private_ip ? local.conductor_private_ip : local.conductor_public_ip
}

output "supervisor_ids" {
  value = var.use_private_ip ? aws_instance.supervisor.*.private_ip : aws_instance.supervisor.*.public_ip
}

output "conductor_ui" {
  value = "http://${var.use_private_ip ? local.conductor_private_ip : local.conductor_public_ip}:8888"
}

output "ec2_console" {
  value = "https://us-west-2.console.aws.amazon.com/ec2/v2/home?region=${var.region}#Instances:tag:Name=${var.cluster_name}-cluster-supervisor,${var.cluster_name}-cluster-conductor,${var.cluster_name}-cluster-zookeeper;instanceState=running;sort=desc:tag:Name"
}

###
# Outputs for Ansible inventory generation
###
output "zookeeper_private_ips" {
  value = local.zk_private_ips
}

output "conductor_private_ip" {
  value = local.conductor_private_ip
}

output "supervisor_private_ips" {
  value = aws_instance.supervisor.*.private_ip
}

output "bastion_host" {
  value = module.vpc.bastion_public_ip
}

output "rama_user" {
  value = var.username
}

output "private_ssh_key" {
  value = var.private_ssh_key
}
