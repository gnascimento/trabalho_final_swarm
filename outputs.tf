########################################
# Saídas
########################################
output "manager_public_ip" {
  description = "IP público do manager"
  value       = aws_instance.manager.public_ip
}

output "manager_private_ip" {
  description = "IP privado do manager"
  value       = aws_instance.manager.private_ip
}

output "worker_private_ips" {
  description = "Lista de IPs privados dos workers"
  value       = [for w in aws_instance.worker : w.private_ip]
}

output "load_balancer_public_ip" {
  description = "IP público do balanceador de carga"
  value       = aws_instance.load_balancer.public_ip
}
