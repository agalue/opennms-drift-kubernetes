# @author Alejandro Galue <agalue@opennms.org>

provider "aws" {
  region = "us-east-2"
}

data "aws_security_group" "nodes" {
  filter {
    name   = "tag:Name"
    values = ["nodes.k8s.opennms.org", "eksctl-opennms-cluster/ClusterSharedNodeSecurityGroup"]
  }
}

resource "aws_security_group_rule" "allow_kafka" {
  type              = "ingress"
  from_port         = 9094
  to_port           = 9094
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${data.aws_security_group.nodes.id}"
}
