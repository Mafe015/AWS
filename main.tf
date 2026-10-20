terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region  = "us-east-2"
  profile = "user_cli"   # autentica con las claves de user_cli, sin contraseñas en el código
}

data "aws_caller_identity" "current" {}

# Red: se usa la VPC por defecto (no se crea red nueva)
data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# ---------- S3 ----------
resource "aws_s3_bucket" "demo" {
  bucket        = "eia-actividad-aws-tf-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Proyecto = "actividad-aws", Metodo = "terraform" }
}

# ---------- Grupos de seguridad ----------
resource "aws_security_group" "ec2" {
  name        = "eia-ec2-tf-sg"
  description = "SG de la EC2 (sin entrada)"
  vpc_id      = data.aws_vpc.default.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Proyecto = "actividad-aws" }
}

resource "aws_security_group" "rds" {
  name        = "eia-rds-tf-sg"
  description = "SG de RDS: MySQL solo desde la EC2"
  vpc_id      = data.aws_vpc.default.id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }
  tags = { Proyecto = "actividad-aws" }
}

# ---------- EC2 ----------
resource "aws_instance" "demo" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.ec2.id]
  tags                   = { Name = "eia-ec2-tf", Proyecto = "actividad-aws" }
}

# ---------- RDS con contraseña administrada por Secrets Manager ----------
resource "aws_db_instance" "demo" {
  identifier                  = "eia-rds-tf"
  engine                      = "mysql"
  instance_class              = "db.t3.micro"
  allocated_storage           = 20
  db_name                     = "demo"
  username                    = "admin"
  manage_master_user_password = true   # RDS crea y guarda la contraseña en Secrets Manager
  vpc_security_group_ids      = [aws_security_group.rds.id]
  publicly_accessible         = false
  backup_retention_period     = 0
  skip_final_snapshot         = true
  deletion_protection         = false
  apply_immediately           = true
  tags                        = { Proyecto = "actividad-aws" }
}

output "bucket"      { value = aws_s3_bucket.demo.bucket }
output "ec2_id"      { value = aws_instance.demo.id }
output "rds_endpoint" { value = aws_db_instance.demo.endpoint }
output "rds_secret_arn" { value = aws_db_instance.demo.master_user_secret[0].secret_arn }