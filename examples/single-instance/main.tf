##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  region     = var.aws_region
}

##################################################################################
# DATA
##################################################################################


data "aws_ami" "vault" {
  most_recent      = true
  owners           = ["self"]

  filter {
    name   = "name"
    values = ["vault-consul-ubuntu16-7c45a76a-a709-48f6-93f1-d4170ec1ca0e"]
  }

}

data "aws_ami" "consul" {
  most_recent      = true
  owners           = ["self"]

  filter {
    name   = "name"
    values = ["consul-ubuntu-a7a56da7-e22d-448d-8865-b032bffa1786"]
  }

}

##################################################################################
# RESOURCES
##################################################################################

# NETWORKING #
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = local.vault_common_tags
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = local.vault_common_tags
}

resource "aws_subnet" "subnet1" {
  cidr_block              = var.vpc_subnet1_cidr_block
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = local.vault_common_tags
}

# ROUTING #
resource "aws_route_table" "rtb" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = local.vault_common_tags
}

resource "aws_route_table_association" "rta-subnet1" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.rtb.id
}

# SECURITY GROUPS #

# Vault security group 
resource "aws_security_group" "vault-sg" {
  name   = "vault_sg"
  vpc_id = aws_vpc.vpc.id

  # HTTP access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.vault_common_tags
}


# Consul security group 
resource "aws_security_group" "consul-sg" {
  name   = "consul_sg"
  vpc_id = aws_vpc.vpc.id

  # HTTP access from anywhere
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_subnet1_cidr_block]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.consul_common_tags
}


# INSTANCES #
resource "aws_instance" "vault" {
  ami                    = data.aws_ami.vault.image_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.subnet1.id
  vpc_security_group_ids = [aws_security_group.vault-sg.id]
  key_name = "EC2-Training"

  user_data = <<EOF
#! /bin/bash
  
   /opt/vault/bin/run-vault --tls-cert-file /opt/vault/tls/vault.crt.pem --tls-key-file /opt/vault/tls/vault.key.pem

EOF

  tags = local.vault_common_tags

}

resource "aws_instance" "consul" {
  ami                    = data.aws_ami.consul.image_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.subnet1.id
  vpc_security_group_ids = [aws_security_group.consul-sg.id,aws_security_group.vault-sg.id]
  key_name = "EC2-Training"
  iam_instance_profile  = aws_iam_instance_profile.instance_profile.id

  user_data = <<EOF
#! /bin/bash
  
  set -e

  # Send the log output from this script to user-data.log, syslog, and the console  
  # From: https://alestic.com/2010/12/ec2-user-data-output/ 
  exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

  sudo /opt/consul/bin/run-consul --server

EOF

  tags = local.consul_common_tags

}




# ---------------------------------------------------------------------------------------------------------------------
# ATTACH AN IAM ROLE TO EACH EC2 INSTANCE
# We can use the IAM role to grant the instance IAM permissions so we can use the AWS CLI without having to figure out
# how to get our secret AWS access keys onto the box.
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_instance_profile" "instance_profile" {

  name_prefix = "consul"
  path        = "/"
  role        = aws_iam_role.instance_role.name

  
}

resource "aws_iam_role" "instance_role" {

  name_prefix        = "consul"
  assume_role_policy = data.aws_iam_policy_document.instance_role.json


}

data "aws_iam_policy_document" "instance_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}




# ---------------------------------------------------------------------------------------------------------------------
# ATTACH AN IAM POLICY THAT ALLOWS THE CONSUL NODES TO AUTOMATICALLY DISCOVER EACH OTHER AND FORM A CLUSTER
# ---------------------------------------------------------------------------------------------------------------------

resource "aws_iam_role_policy" "auto_discover_cluster" {
  name   = "auto-discover-cluster"
  role   = aws_iam_role.instance_role.id
  policy = data.aws_iam_policy_document.auto_discover_cluster.json
}

data "aws_iam_policy_document" "auto_discover_cluster" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "autoscaling:DescribeAutoScalingGroups",
    ]

    resources = ["*"]
  }
}

