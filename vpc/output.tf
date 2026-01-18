output node_instance_profile_name {
  value = aws_iam_instance_profile.rama.name
}

output vpc_id {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output node_security_group_id {
  value = aws_security_group.rama.id
}

output node_subnet_id {
  value = aws_subnet.private[0].id
}

output bastion_public_ip {
  value = aws_instance.bastion.public_ip
}
