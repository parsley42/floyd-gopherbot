variable "robot-name" {
  type        = string
  description = "The robot's name, required for provisioning multiple"
  default     = "gopherbot"
}

variable "encryption-key" {
  type        = string
  description = "The robot's brain encryption key, should be in <bot-name>.auto.tfvars file"
}

variable "deploy-key" {
  type        = string
  description = "The robot's read-only ssh deployment private key"
}

variable "wg-key" {
  type        = string
  description = "The robot's private wireguard key"
}

variable "wg-pub" {
  type        = string
  description = "The robot's public wireguard key"
}

variable "repository" {
  type        = string
  description = "The robot's configuration repository"
}

variable "protocol" {
  type        = string
  description = "The chat connection protocol to use, only 'slack' currently supported"
  default     = "slack"
}

variable "instance-type" {
  type        = string
  description = "The AWS instance type to launch"
  default     = "t3.micro"
}

variable "vpc_name" {
  type        = string
  description = "The name of the vpc where the instance should launch"
  default     = ""
}

variable "tags" {
  default     = {}
  description = "Instance tags"
  type        = map(string)
}
