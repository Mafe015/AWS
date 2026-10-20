import boto3, time

REGION = "us-east-2"
session = boto3.Session(profile_name="user_cli", region_name=REGION)
ec2 = session.client("ec2")
s3 = session.client("s3")
rds = session.client("rds")
ssm = session.client("ssm")
sts = session.client("sts")

cuenta = sts.get_caller_identity()["Account"]
BUCKET = f"eia-actividad-aws-boto3-{cuenta}"
TAG = [{"Key": "Proyecto", "Value": "actividad-aws"}, {"Key": "Metodo", "Value": "boto3"}]

# VPC por defecto
vpc_id = ec2.describe_vpcs(Filters=[{"Name": "isDefault", "Values": ["true"]}])["Vpcs"][0]["VpcId"]

# S3 (us-east-2 exige LocationConstraint)
s3.create_bucket(Bucket=BUCKET, CreateBucketConfiguration={"LocationConstraint": REGION})
print("Bucket:", BUCKET)

# Grupos de seguridad
sg_ec2 = ec2.create_security_group(GroupName="eia-ec2-boto3-sg", Description="SG EC2 sin entrada",
                                   VpcId=vpc_id,
                                   TagSpecifications=[{"ResourceType": "security-group", "Tags": TAG}])["GroupId"]
sg_rds = ec2.create_security_group(GroupName="eia-rds-boto3-sg", Description="SG RDS MySQL solo desde EC2",
                                   VpcId=vpc_id,
                                   TagSpecifications=[{"ResourceType": "security-group", "Tags": TAG}])["GroupId"]
ec2.authorize_security_group_ingress(GroupId=sg_rds, IpPermissions=[{
    "IpProtocol": "tcp", "FromPort": 3306, "ToPort": 3306,
    "UserIdGroupPairs": [{"GroupId": sg_ec2}]}])

# EC2 (AMI Amazon Linux 2023 desde SSM)
ami = ssm.get_parameter(Name="/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64")["Parameter"]["Value"]
inst = ec2.run_instances(ImageId=ami, InstanceType="t3.micro", MinCount=1, MaxCount=1,
                         SecurityGroupIds=[sg_ec2],
                         TagSpecifications=[{"ResourceType": "instance",
                                             "Tags": TAG + [{"Key": "Name", "Value": "eia-ec2-boto3"}]}])
ec2_id = inst["Instances"][0]["InstanceId"]
print("EC2:", ec2_id)

# RDS con contraseña administrada por Secrets Manager
rds.create_db_instance(DBInstanceIdentifier="eia-rds-boto3", Engine="mysql",
                       DBInstanceClass="db.t3.micro", AllocatedStorage=20,
                       DBName="demo", MasterUsername="admin",
                       ManageMasterUserPassword=True,
                       VpcSecurityGroupIds=[sg_rds], PubliclyAccessible=False,
                       BackupRetentionPeriod=0, Tags=TAG)
print("RDS creándose (5-10 min)...")
rds.get_waiter("db_instance_available").wait(DBInstanceIdentifier="eia-rds-boto3")
db = rds.describe_db_instances(DBInstanceIdentifier="eia-rds-boto3")["DBInstances"][0]
print("Endpoint:", db["Endpoint"]["Address"])
print("Secreto:", db["MasterUserSecret"]["SecretArn"])