resource "aws_dynamodb_table" "robot-brain" {
  name           = "${var.robot-name}-brain"
  billing_mode   = "PROVISIONED"
  # Note: AWS free tier includes 25GB + 25 read and 25 write units
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "Memory"

  attribute {
    name = "Memory"
    type = "S"
  }
}
