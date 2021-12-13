packer {
  required_version = ">= 1.5.4"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "ca_public_key_path" {
  type = string
}

variable "consul_download_url" {
  type    = string
  default = "${env("CONSUL_DOWNLOAD_URL")}"
}

variable "consul_module_version" {
  type    = string
  default = "v0.8.0"
}

variable "consul_version" {
  type    = string
  default = "1.9.2"
}

variable "install_auth_signing_script" {
  type    = string
  default = "true"
}

variable "tls_private_key_path" {
  type = string
}

variable "tls_public_key_path" {
  type = string
}

variable "vault_download_url" {
  type    = string
  default = "${env("VAULT_DOWNLOAD_URL")}"
}

variable "vault_version" {
  type    = string
  default = "1.6.1"
}

data "amazon-ami" "amzn2" {
  filters = {
    architecture                       = "x86_64"
    "block-device-mapping.volume-type" = "gp2"
    name                               = "*amzn2-ami-hvm-*"
    root-device-type                   = "ebs"
    virtualization-type                = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = "${var.aws_region}"
}

data "amazon-ami" "ubuntu16" {
  filters = {
    architecture                       = "x86_64"
    "block-device-mapping.volume-type" = "gp2"
    name                               = "ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"
    root-device-type                   = "ebs"
    virtualization-type                = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "${var.aws_region}"
}

data "amazon-ami" "ubuntu18" {
  filters = {
    architecture                       = "x86_64"
    "block-device-mapping.volume-type" = "gp2"
    name                               = "ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"
    root-device-type                   = "ebs"
    virtualization-type                = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]
  region      = "${var.aws_region}"
}

# 1 error occurred upgrading the following block:
# unhandled "clean_resource_name" call:
# there is no way to automatically upgrade the "clean_resource_name" call.
# Please manually upgrade to use custom validation rules, `replace(string, substring, replacement)` or `regex_replace(string, substring, replacement)`
# Visit https://packer.io/docs/templates/hcl_templates/variables#custom-validation-rules , https://www.packer.io/docs/templates/hcl_templates/functions/string/replace or https://www.packer.io/docs/templates/hcl_templates/functions/string/regex_replace for more infos.

source "amazon-ebs" "amazon-linux-2-ami" {
  ami_description = "An Amazon Linux 2 AMI that has Vault and Consul installed."
  ami_name        = "vault-consul-amazon-linux-2-${uuidv4()}"
  instance_type   = "t2.micro"
  region          = "${var.aws_region}"
  source_ami      = "${data.amazon-ami.amzn2.id}"
  ssh_username    = "ec2-user"
}

# 1 error occurred upgrading the following block:
# unhandled "clean_resource_name" call:
# there is no way to automatically upgrade the "clean_resource_name" call.
# Please manually upgrade to use custom validation rules, `replace(string, substring, replacement)` or `regex_replace(string, substring, replacement)`
# Visit https://packer.io/docs/templates/hcl_templates/variables#custom-validation-rules , https://www.packer.io/docs/templates/hcl_templates/functions/string/replace or https://www.packer.io/docs/templates/hcl_templates/functions/string/regex_replace for more infos.

source "amazon-ebs" "ubuntu16-ami" {
  ami_description = "An Ubuntu 16.04 AMI that has Vault and Consul installed."
  ami_name        = "vault-consul-ubuntu16-${uuidv4()}"
  instance_type   = "t2.micro"
  region          = "${var.aws_region}"
  source_ami      = "${data.amazon-ami.ubuntu16.id}"
  ssh_username    = "ubuntu"
}

# 1 error occurred upgrading the following block:
# unhandled "clean_resource_name" call:
# there is no way to automatically upgrade the "clean_resource_name" call.
# Please manually upgrade to use custom validation rules, `replace(string, substring, replacement)` or `regex_replace(string, substring, replacement)`
# Visit https://packer.io/docs/templates/hcl_templates/variables#custom-validation-rules , https://www.packer.io/docs/templates/hcl_templates/functions/string/replace or https://www.packer.io/docs/templates/hcl_templates/functions/string/regex_replace for more infos.

source "amazon-ebs" "ubuntu18-ami" {
  ami_description = "An Ubuntu 18.04 AMI that has Vault and Consul installed."
  ami_name        = "vault-consul-ubuntu18-${uuidv4()}"
  instance_type   = "t2.micro"
  region          = "${var.aws_region}"
  source_ami      = "${data.amazon-ami.ubuntu18.id}"
  ssh_username    = "ubuntu"
}

build {
  sources = ["source.amazon-ebs.amazon-linux-2-ami", "source.amazon-ebs.ubuntu16-ami", "source.amazon-ebs.ubuntu18-ami"]

  provisioner "shell" {
    inline = ["mkdir -p /tmp/terraform-aws-vault/modules"]
  }

  provisioner "file" {
    destination  = "/tmp/terraform-aws-vault/modules"
    pause_before = "30s"
    source       = "${path.root}/../../modules/"
  }

  provisioner "shell" {
    inline = ["if test -n \"${var.vault_download_url}\"; then", " /tmp/terraform-aws-vault/modules/install-vault/install-vault --download-url ${var.vault_download_url};", "else", " /tmp/terraform-aws-vault/modules/install-vault/install-vault --version ${var.vault_version};", "fi"]
  }

  provisioner "file" {
    destination = "/tmp/sign-request.py"
    source      = "${path.root}/auth/sign-request.py"
  }

  provisioner "file" {
    destination = "/tmp/ca.crt.pem"
    source      = "${var.ca_public_key_path}"
  }

  provisioner "file" {
    destination = "/tmp/vault.crt.pem"
    source      = "${var.tls_public_key_path}"
  }

  provisioner "file" {
    destination = "/tmp/vault.key.pem"
    source      = "${var.tls_private_key_path}"
  }

  provisioner "shell" {
    inline         = ["if [[ '${var.install_auth_signing_script}' == 'true' ]]; then", "sudo mv /tmp/sign-request.py /opt/vault/scripts/", "else", "sudo rm /tmp/sign-request.py", "fi", "sudo mv /tmp/ca.crt.pem /opt/vault/tls/", "sudo mv /tmp/vault.crt.pem /opt/vault/tls/", "sudo mv /tmp/vault.key.pem /opt/vault/tls/", "sudo chown -R vault:vault /opt/vault/tls/", "sudo chmod -R 600 /opt/vault/tls", "sudo chmod 700 /opt/vault/tls", "sudo /tmp/terraform-aws-vault/modules/update-certificate-store/update-certificate-store --cert-file-path /opt/vault/tls/ca.crt.pem"]
    inline_shebang = "/bin/bash -e"
  }

  provisioner "shell" {
    inline         = ["sudo apt-get install -y git", "if [[ '${var.install_auth_signing_script}' == 'true' ]]; then", "sudo apt-get install -y python-pip", "LC_ALL=C && sudo pip install boto3", "fi"]
    inline_shebang = "/bin/bash -e"
    only           = ["ubuntu16-ami", "ubuntu18-ami"]
  }

  provisioner "shell" {
    inline = ["sudo yum install -y git", "if [[ '${var.install_auth_signing_script}' == 'true' ]]; then", "sudo yum install -y python2-pip", "LC_ALL=C && sudo pip install boto3", "fi"]
    only   = ["amazon-linux-2-ami"]
  }

  provisioner "shell" {
    inline       = ["git clone --branch ${var.consul_module_version} https://github.com/hashicorp/terraform-aws-consul.git /tmp/terraform-aws-consul", "if test -n \"${var.consul_download_url}\"; then", " /tmp/terraform-aws-consul/modules/install-consul/install-consul --download-url ${var.consul_download_url};", "else", " /tmp/terraform-aws-consul/modules/install-consul/install-consul --version ${var.consul_version};", "fi"]
    pause_before = "30s"
  }

  provisioner "shell" {
    inline = ["/tmp/terraform-aws-consul/modules/install-dnsmasq/install-dnsmasq"]
    only   = ["ubuntu16-ami", "amazon-linux-2-ami"]
  }

  provisioner "shell" {
    inline       = ["/tmp/terraform-aws-consul/modules/setup-systemd-resolved/setup-systemd-resolved"]
    only         = ["ubuntu18-ami"]
    pause_before = "30s"
  }

}
