data "aws_vpc" "bot-vpc" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_subnets" "bot-subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.bot-vpc.id]
  }
}

resource "aws_security_group" "bot-sg" {
  name        = "${var.robot-name}-allow-wireguard"
  description = "Allows the robot to provide WireGuard VPN server services"
  vpc_id      = data.aws_vpc.bot-vpc.id

  ingress {
    description      = "WireGuard UDP"
    from_port        = 51820
    to_port          = 51820
    protocol         = "udp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_wireguard"
  }
}
