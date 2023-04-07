data "aws_ami" "amazon-linux-2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-20*-x86_64"]
  }
}

locals {
  # Define the bootstrap script as a local variable
  bootstrap_script = templatefile("${path.module}/bootstrap.tpl", {
    bot_name   = var.robot-name
    vpn_cidr   = var.vpn-cidr
    wg_private = var.wg-key
    bot_repo   = var.repository
    protocol   = var.protocol
    bot_key    = var.encryption-key
    deploy_key = var.deploy-key
  })
}

resource "aws_launch_template" "bot-template" {
  name                                 = "${var.robot-name}_template"
  image_id                             = data.aws_ami.amazon-linux-2023.id
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = var.instance-type
  update_default_version               = true

  user_data = base64encode(local.bootstrap_script)

  iam_instance_profile {
    name = aws_iam_instance_profile.bot_profile.name
  }
  monitoring {
    enabled = false
  }
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.bot-sg.id]
  }
}

resource "aws_autoscaling_group" "immortal-bot" {
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1
  vpc_zone_identifier = data.aws_subnets.bot-subnets.ids
  # Allow the robot to find out who it is by introspection
  tag {
    key                 = "robot-name"
    value               = var.robot-name
    propagate_at_launch = true
  }
  tag {
    key                 = "Name"
    value               = "${var.robot-name}-robot"
    propagate_at_launch = true
  }
  launch_template {
    name = aws_launch_template.bot-template.name
  }
}
