locals {
  default_tags = {
    Resprefix = local.res_prefix
    Workspace = terraform.workspace
    Terraform = "true"
    Project = "Rama"
  }
  res_prefix = var.res_prefix
}

data "aws_availability_zones" "main" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = merge(local.default_tags, {
    Name = "${local.res_prefix}-rama-vpc"
  })
}

resource "aws_subnet" "public" {
  count                   = var.public-subnet-count
  availability_zone       = data.aws_availability_zones.main.names[count.index]
  cidr_block              = "10.0.${count.index}.0/24"
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id

  tags = merge(local.default_tags, {
    Name       = "${local.res_prefix}-public-subnet-${count.index}"
    SubnetType = "public"
  })
}

resource "aws_subnet" "private" {
  count                   = var.private-subnet-count
  availability_zone       = data.aws_availability_zones.main.names[count.index]
  cidr_block              = "10.0.${count.index + 100}.0/24"
  map_public_ip_on_launch = false
  vpc_id                  = aws_vpc.main.id

  tags = merge(local.default_tags, {
    Name       = "${local.res_prefix}-private-subnet-${count.index}"
    SubnetType = "private"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.default_tags, {
    Name = "${local.res_prefix}-igw"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.default_tags, {
    Name = "${local.res_prefix}-nat-eip"
  })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.default_tags, {
    Name = "${local.res_prefix}-nat-gw"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.default_tags, {
    Name       = "${local.res_prefix}-public-route-table"
    SubnetType = "public"
  })
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = var.public-subnet-count
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public[count.index].id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.default_tags, {
    Name       = "${local.res_prefix}-private-route-table"
    SubnetType = "private"
  })
}

resource "aws_route" "private" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private" {
  count          = var.private-subnet-count
  route_table_id = aws_route_table.private.id
  subnet_id      = aws_subnet.private[count.index].id
}

resource "aws_security_group" "rama" {
  name        = "${local.res_prefix}-rama-sg"
  description = "Security group for Rama cluster"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.default_tags, {
    Name = "${local.res_prefix}-rama-sg"
  })

}

resource "aws_vpc_security_group_ingress_rule" "rama-instance-connect" {
  security_group_id            = aws_security_group.rama.id
  referenced_security_group_id = aws_security_group.ic.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rama-bastion" {
  security_group_id            = aws_security_group.rama.id
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = 0
  to_port                      = 65535
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rama-internal" {
  security_group_id            = aws_security_group.rama.id
  referenced_security_group_id = aws_security_group.rama.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "rama-egress" {
  security_group_id = aws_security_group.rama.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_vpc_security_group_egress_rule" "rama-ic-egress" {
  security_group_id = aws_security_group.ic.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

resource "aws_security_group" "ic" {
  name        = "${local.res_prefix}-rama-ic"
  description = "Security group for instance connect"

  vpc_id = aws_vpc.main.id

  tags = merge(local.default_tags, {
    Name = "${local.res_prefix}-rama-ic-sg"
  })
}

resource "aws_ec2_instance_connect_endpoint" "rama" {
  subnet_id = aws_subnet.private[0].id

  security_group_ids = [aws_security_group.ic.id]

  tags = merge(local.default_tags, {
    Name = "${local.res_prefix}-ic"
  })
}

resource "aws_iam_instance_profile" "rama" {
  name = "${local.res_prefix}-rama-node-ip"
  role = aws_iam_role.rama.name
}

resource "aws_iam_role" "rama" {
  name = "${local.res_prefix}-rama-ip-role"
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

resource "aws_iam_role_policy_attachment" "rama-ssm-policy-attachment" {
  role       = aws_iam_role.rama.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
