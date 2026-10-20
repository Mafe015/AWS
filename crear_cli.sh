#!/bin/bash
set -e
export AWS_PROFILE=user_cli
export AWS_DEFAULT_REGION=us-east-2

CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="eia-actividad-aws-cli-$CUENTA"
VPC=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text)

# S3
aws s3api create-bucket --bucket $BUCKET \
  --create-bucket-configuration LocationConstraint=us-east-2
echo "Bucket: $BUCKET"

# Grupos de seguridad
SG_EC2=$(aws ec2 create-security-group --group-name eia-ec2-cli-sg \
  --description "SG EC2 sin entrada" --vpc-id $VPC --query GroupId --output text)
SG_RDS=$(aws ec2 create-security-group --group-name eia-rds-cli-sg \
  --description "SG RDS MySQL solo desde EC2" --vpc-id $VPC --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_RDS \
  --protocol tcp --port 3306 --source-group $SG_EC2
echo "SGs: $SG_EC2 $SG_RDS"

# EC2
AMI=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text)
aws ec2 run-instances --image-id $AMI --instance-type t3.micro \
  --security-group-ids $SG_EC2 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=eia-ec2-cli},{Key=Proyecto,Value=actividad-aws},{Key=Metodo,Value=cli}]' \
  --query "Instances[0].InstanceId" --output text

# RDS con contraseña administrada por Secrets Manager
aws rds create-db-instance --db-instance-identifier eia-rds-cli \
  --engine mysql --db-instance-class db.t3.micro --allocated-storage 20 \
  --db-name demo --master-username admin --manage-master-user-password \
  --vpc-security-group-ids $SG_RDS --no-publicly-accessible \
  --backup-retention-period 0 \
  --tags Key=Proyecto,Value=actividad-aws Key=Metodo,Value=cli
echo "RDS creándose (5-10 min)..."
aws rds wait db-instance-available --db-instance-identifier eia-rds-cli
aws rds describe-db-instances --db-instance-identifier eia-rds-cli \
  --query "DBInstances[0].[DBInstanceStatus,Endpoint.Address,MasterUserSecret.SecretArn]"