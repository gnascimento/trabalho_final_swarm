########################################
# main.tf
########################################


########################################
# VPC
########################################
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-subnet"
  }
}

resource "aws_internet_gateway" "main_igw" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_route_table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_nat_gateway" "main_nat_gw" {
  allocation_id = aws_eip.main_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "main-nat-gw"
  }
}

resource "aws_eip" "main_eip" {
  vpc = true
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main_nat_gw.id
  }

  tags = {
    Name = "private-route-table"
  }
}

resource "aws_route_table_association" "private_route_table_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

########################################
# Security Group
########################################
resource "aws_security_group" "docker_sg" {
  name        = "docker-swarm-sg"
  description = "Permite trafego SSH, Swarm e porta 8080"
  vpc_id      = aws_vpc.main_vpc.id

  # Porta SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Portas Docker Swarm
  # 2377 (cluster management), 7946 (TCP/UDP node communication), 4789 (overlay)
  ingress {
    description = "Docker Swarm manager port"
    from_port   = 2377
    to_port     = 2377
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.private_subnet.cidr_block]
  }
  ingress {
    description = "Docker Swarm overlay network TCP"
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.private_subnet.cidr_block]
  }
  ingress {
    description = "Docker Swarm overlay network UDP"
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    cidr_blocks = [aws_subnet.private_subnet.cidr_block]
  }
  ingress {
    description = "Docker Swarm overlay network 2 (UDP)"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    cidr_blocks = [aws_subnet.private_subnet.cidr_block]
  }

  # Porta 8080
  ingress {
    description = "Aplicacao na porta 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Saída liberada
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "docker-swarm-sg"
  }
}




resource "aws_security_group" "haproxy_sg" {
  name        = "haproxy-sg"
  description = "Permite trafego SSH e HTTP"
  vpc_id      = aws_vpc.main_vpc.id

  # Porta SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  # Porta 80
  ingress {
    description = "Aplicacao na porta 80"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Saída liberada
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "docker-swarm-sg"
  }
}



########################################
# Nó Manager
########################################
resource "aws_instance" "manager" {
  ami                    = data.aws_ami.amazon_linux2.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.docker_sg.id]
  key_name               = var.aws_key_pair_name
  subnet_id              = aws_subnet.private_subnet.id
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_instance_profile.name

  tags = {
    Name = "docker-manager"
  }

  user_data = <<-EOF
    #!/bin/bash
    # Atualiza pacotes
    yum update -y
    # Instala Docker
    amazon-linux-extras install docker -y
    service docker start
    systemctl enable docker

    # Adiciona o usuário ec2-user ao grupo docker
    sudo usermod -aG docker ec2-user

    # Inicia o Swarm
    PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
    docker swarm init --advertise-addr $PRIVATE_IP

    # Salva token de worker no SSM Parameter Store
    aws ssm put-parameter --name "/docker/swarm/worker/token" --value "$(docker swarm join-token worker -q)" --type "String" --overwrite --region=us-east-1

    # Inicia o serviço de exemplo
    docker service create --replicas 3 --name hellogo -p8080:8080 gnascimento/hellogo:latest
   
    # Fim do script
  EOF
}

########################################
# Nós Workers (2 unidades)
########################################
resource "aws_instance" "worker" {
  count                  = 2
  depends_on = [ aws_instance.manager ]
  ami                    = data.aws_ami.amazon_linux2.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.docker_sg.id]
  key_name               = var.aws_key_pair_name
  subnet_id              = aws_subnet.private_subnet.id
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm_instance_profile.name

  tags = {
    Name = "docker-worker-${count.index}"
  }

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    amazon-linux-extras install docker -y
    service docker start
    systemctl enable docker
    sudo usermod -aG docker ec2-user

    # Cria o script de inicialização
    cat <<'EOT' > /usr/local/bin/join_swarm.sh
    #!/bin/bash
    WORKER_TOKEN=$(aws ssm get-parameter --name "/docker/swarm/worker/token" --query "Parameter.Value" --output text --region us-east-1)
    MANAGER_IP="${aws_instance.manager.private_ip}"
    docker swarm join --token $WORKER_TOKEN $MANAGER_IP:2377
    EOT

    chmod +x /usr/local/bin/join_swarm.sh

    # Cria o serviço systemd
    cat <<'EOT' > /etc/systemd/system/join_swarm.service
    [Unit]
    Description=Join Docker Swarm
    After=docker.service

    [Service]
    ExecStart=/usr/local/bin/join_swarm.sh
    Restart=always

    [Install]
    WantedBy=multi-user.target
    EOT

    # Habilita e inicia o serviço
    systemctl enable join_swarm.service
    systemctl start join_swarm.service
  EOF
}

########################################
# Balanceador de Carga (HAProxy)
########################################
resource "aws_instance" "load_balancer" {
  ami                         = data.aws_ami.amazon_linux2.id
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [aws_security_group.haproxy_sg.id]
  key_name                    = var.aws_key_pair_name
  subnet_id                   = aws_subnet.public_subnet.id
  associate_public_ip_address = true
  tags = {
    Name = "haproxy-load-balancer"
  }

  user_data = <<-EOF
    #!/bin/bash
    # Atualiza pacotes
    yum update -y
    # Instala HAProxy
    yum install -y haproxy

    sudo mkdir -p /run/haproxy
    sudo chown -R haproxy:haproxy /run/haproxy
    sudo chmod -R 755 /run/haproxy

    # Configura o rsyslog para aceitar logs do HAProxy
    echo 'local0.* /var/log/haproxy.log' >> /etc/rsyslog.conf
    systemctl restart rsyslog

    # Configura HAProxy
    cat <<EOT > /etc/haproxy/haproxy.cfg
    global
        log /dev/log    local0
        log /dev/log    local1 notice
        chroot /var/lib/haproxy
        stats socket /run/haproxy/admin.sock mode 660 level admin
        stats timeout 30s
        user haproxy
        group haproxy
        daemon

    defaults
        log     global
        mode    http
        option  httplog
        option  dontlognull
        timeout connect 5000
        timeout client  50000
        timeout server  50000

    frontend http_front
        bind *:80
        default_backend http_back

    backend http_back
        balance roundrobin
        server worker1 ${aws_instance.worker[0].private_ip}:8080 check
        server worker2 ${aws_instance.worker[1].private_ip}:8080 check
        server worker3 ${aws_instance.manager.private_ip}:8080 check
    EOT

    # Inicia HAProxy
    systemctl enable haproxy
    systemctl start haproxy
  EOF
}