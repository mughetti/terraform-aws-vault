output "aws_instance_public_dns" {
  value = aws_instance.vault.public_dns
}
output "aws_instance_public_ip" {
  value = aws_instance.vault.public_ip
}