data "aws_route53_zone" "main" {
  name         = "luccamedina.ownboarding.teratest.net"
  private_zone = false
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }
}