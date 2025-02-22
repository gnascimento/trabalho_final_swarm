# Obter AMI do Amazon Linux 2 (x86_64) mais recente
data "aws_ami" "amazon_linux2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["137112412989"] # Conta oficial da Amazon
}

data "aws_caller_identity" "current" {}