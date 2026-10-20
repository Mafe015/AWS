import boto3

REGION = "us-east-2"
session = boto3.Session(profile_name="user_cli", region_name=REGION)
ec2 = session.client("ec2")
s3 = session.client("s3")
rds = session.client("rds")
cuenta = session.client("sts").get_caller_identity()["Account"]
BUCKET = f"eia-actividad-aws-boto3-{cuenta}"

# RDS (primero, tarda más)
rds.delete_db_instance(DBInstanceIdentifier="eia-rds-boto3", SkipFinalSnapshot=True,
                       DeleteAutomatedBackups=True)
print("Eliminando RDS...")

# EC2
ids = [i["InstanceId"] for r in ec2.describe_instances(
        Filters=[{"Name": "tag:Name", "Values": ["eia-ec2-boto3"]},
                 {"Name": "instance-state-name", "Values": ["pending", "running", "stopped"]}]
       )["Reservations"] for i in r["Instances"]]
if ids:
    ec2.terminate_instances(InstanceIds=ids)
    ec2.get_waiter("instance_terminated").wait(InstanceIds=ids)
    print("EC2 terminada")

# S3
s3.delete_bucket(Bucket=BUCKET)
print("Bucket eliminado")

# Esperar a RDS y borrar grupos de seguridad
rds.get_waiter("db_instance_deleted").wait(DBInstanceIdentifier="eia-rds-boto3")
print("RDS eliminada")
for nombre in ["eia-rds-boto3-sg", "eia-ec2-boto3-sg"]:
    sg = ec2.describe_security_groups(Filters=[{"Name": "group-name", "Values": [nombre]}])["SecurityGroups"]
    if sg:
        ec2.delete_security_group(GroupId=sg[0]["GroupId"])
        print("SG eliminado:", nombre)