data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

resource "aws_iam_instance_profile" "bot_profile" {
  name = "${var.robot-name}_bot_profile"
  role = aws_iam_role.bot_role.name
}

resource "aws_iam_role" "bot_role" {
  name = "${var.robot-name}_bot_role"
  path = "/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess",
  ]
  inline_policy {
    name = "bot-brain-access"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          "Effect" : "Allow",
          "Action" : [
            "dynamodb:PutItem",
            "dynamodb:Scan",
            "dynamodb:DescribeTable",
            "dynamodb:GetItem",
            "dynamodb:DeleteItem"
          ],
          "Resource" : "${aws_dynamodb_table.robot-brain.arn}"
        }
      ]
    })
  }
}
