#!/bin/bash
export AWS_PROFILE=user_cli
export AWS_DEFAULT_REGION=us-east-2
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="eia-actividad-aws-cli-$CUENTA"

aws rds delete-db-instance --db-instance-identifier eia-rds-cli \
  --skip-final-snapshot --delete-automated-backups > /dev/null
echo "Eliminando RDS..."

IDS=$(aws ec2 describe-instances \
  --filters Name=tag:Name,Values=eia-ec2-cli Name=instance-state-name,Values=pending,running,stopped \
  --query "Reservations[].Instances[].InstanceId" --output text)
if [ -n "$IDS" ]; then
  aws ec2 terminate-instances --instance-ids $IDS > /dev/null
  aws ec2 wait instance-terminated --instance-ids $IDS
  echo "EC2 terminada"
fi

aws s3api delete-bucket --bucket $BUCKET
echo "Bucket eliminado"

aws rds wait db-instance-deleted --db-instance-identifier eia-rds-cli
echo "RDS eliminada"

for N in eia-rds-cli-sg eia-ec2-cli-sg; do
  ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=$N \
       --query "SecurityGroups[0].GroupId" --output text)
  [ "$ID" != "None" ] && aws ec2 delete-security-group --group-id $ID && echo "SG eliminado: $N"
done