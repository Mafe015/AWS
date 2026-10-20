import json
import boto3
from botocore.exceptions import ClientError

SECRET_ID = "eia/prueba/db-credentials"
REGION = "us-east-2"

def obtener_secreto():
    session = boto3.Session(profile_name="app_lector", region_name=REGION)
    client = session.client("secretsmanager")
    try:
        resp = client.get_secret_value(SecretId=SECRET_ID)
    except ClientError as e:
        raise RuntimeError(f"No se pudo leer el secreto: {e.response['Error']['Code']}")
    return json.loads(resp["SecretString"]), resp["VersionId"]

if __name__ == "__main__":
    datos, version = obtener_secreto()
    print("Usuario:", datos["username"])
    print("Versión:", version)