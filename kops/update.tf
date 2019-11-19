# @author Alejandro Galue <agalue@opennms.org>

variable "region" {
  description = "AWS Region"
}

variable "domain" {
  description = "Domain Name (e.x. aws.agalue.net)"
}

provider "aws" {
  region = var.region
}

data "aws_security_group" "nodes" {
  filter {
    name   = "tag:Name"
    values = ["nodes.${var.domain}"]
  }
}

resource "aws_security_group_rule" "allow_kafka" {
  type              = "ingress"
  from_port         = 9094
  to_port           = 9094
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = data.aws_security_group.nodes.id
}

