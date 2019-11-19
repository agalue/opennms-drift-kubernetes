# @author Alejandro Galue <agalue@opennms.org>

variable "region" {
  description = "AWS Region"
}

provider "aws" {
  region = var.region
}

data "aws_security_group" "nodes" {
  filter {
    name   = "tag:Name"
    values = ["eks-cluster-sg-opennms-*"]
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

