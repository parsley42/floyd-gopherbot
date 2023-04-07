locals {
  bot-prefix = "/robots/${var.robot-name}"
}

resource "aws_ssm_parameter" "encryption-key" {
  name        = "${local.bot-prefix}/encryption_key"
  description = "The robot's brain encryption key"
  type        = "SecureString"
  value       = var.encryption-key
}

resource "aws_ssm_parameter" "deploy-key" {
  name        = "${local.bot-prefix}/deploy_key"
  description = "The robot's read-only ssh deploy key"
  type        = "String"
  value       = var.deploy-key
}

resource "aws_ssm_parameter" "wg-key" {
  name        = "${local.bot-prefix}/wireguard/wg_key"
  description = "The robot's private wireguard key"
  type        = "SecureString"
  value       = var.wg-key
}
