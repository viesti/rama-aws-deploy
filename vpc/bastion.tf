locals {
  bastion_name = "${local.res_prefix}-rama-bastion"
}

resource "aws_instance" "bastion" {
  instance_type = "t4g.nano"
  ami           = "ami-03369232c34f4fbe9"

  key_name = var.bastion_key_name

  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.bastion.id]

  iam_instance_profile = aws_iam_instance_profile.bastion.name

  root_block_device {
    volume_type = "gp2"
    volume_size = 8
  }

  tags = {
    Name = local.bastion_name
  }

  volume_tags = {
    Name = local.bastion_name
  }
}

resource "aws_security_group" "bastion" {
  name        = "${local.res_prefix}-bastion"
  description = "Security group for bastion use via SSM"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = local.bastion_name
  }
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${local.res_prefix}-bastion-ip"
  role = aws_iam_role.bastion.name
}

resource "aws_iam_role" "bastion" {
  name = "${local.res_prefix}-bastion-role"
  path = "/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bastion-ssm-policy-attachment" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_vpc_security_group_ingress_rule" "rama-bastion-instance-connect" {
  security_group_id            = aws_security_group.bastion.id
  referenced_security_group_id = aws_security_group.ic.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rama-bastion-public-internet" {
  security_group_id            = aws_security_group.bastion.id
  from_port                    = 22
  to_port                      = 22
  ip_protocol                  = "tcp"
  cidr_ipv4                    = "0.0.0.0/0"
}
