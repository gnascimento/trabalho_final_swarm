########################################
# Variáveis
########################################
variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_key_pair_name" {
  type    = string
  default = "GabeKeys" 
  # Altere para o nome da sua chave existente na AWS.
}