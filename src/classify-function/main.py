import json
import os
import traceback

import boto3
import functions_framework
import vertexai
from azure.communication.email import EmailClient
from botocore.config import Config
from google.cloud import secretmanager
from vertexai.generative_models import GenerativeModel, Part


# Environment variables (non-sensitive)
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
NOTIFICATION_EMAIL = os.environ.get("NOTIFICATION_EMAIL", "")
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "")
GCP_LOCATION = os.environ.get("GCP_LOCATION", "us-central1")
EXPECTED_AUTH_TOKEN = os.environ.get("EXPECTED_AUTH_TOKEN", "")

# Secret Manager client (initialized once)
secret_client = secretmanager.SecretManagerServiceClient()

# Cache for secrets (avoid repeated API calls)
_secrets_cache = {}

# Validate required environment variables at startup
REQUIRED_ENV_VARS = [
    "S3_BUCKET_NAME",
    "AWS_REGION",
    "NOTIFICATION_EMAIL",
    "GCP_PROJECT_ID",
    "GCP_LOCATION",
    "EXPECTED_AUTH_TOKEN"
]

def validate_environment():
    """Validate all required environment variables are set."""
    missing = [var for var in REQUIRED_ENV_VARS if not os.environ.get(var)]
    if missing:
        raise RuntimeError(f"Missing required environment variables: {', '.join(missing)}")

# Validate at module load time
validate_environment()


def get_secret(secret_id: str) -> str:
    """
    Retrieve a secret from GCP Secret Manager with caching.
    """
    if secret_id in _secrets_cache:
        return _secrets_cache[secret_id]

    name = f"projects/{GCP_PROJECT_ID}/secrets/{secret_id}/versions/latest"
    try:
        response = secret_client.access_secret_version(request={"name": name})
        secret_value = response.payload.data.decode("UTF-8")
        _secrets_cache[secret_id] = secret_value
        return secret_value
    except Exception as e:
        print(f"CRITICAL: Error retrieving secret {secret_id}: {e}")
        print(f"Ensure secret exists and service account has secretmanager.secretAccessor role")
        raise RuntimeError(f"Failed to retrieve secret {secret_id}") from e


@functions_framework.http
def classify_image(request):
    """
    HTTP Cloud Function that:
    1. Validates authentication token
    2. Downloads an image from S3
    3. Classifies it using Vertex AI Gemini
    4. Sends the results via Azure Communication Services email
    """
    try:
        # Step 0: Verify authentication
        auth_header = request.headers.get("X-Auth-Token", "")
        if not auth_header or auth_header != EXPECTED_AUTH_TOKEN:
            print("Unauthorized access attempt")
            return json.dumps({"error": "Unauthorized"}), 401
        # Parse the incoming request
        request_json = request.get_json(silent=True)
        if not request_json:
            return json.dumps({"error": "No JSON payload received"}), 400

        bucket = request_json.get("bucket", S3_BUCKET_NAME)
        key = request_json.get("key", "")

        if not bucket or not key:
            return json.dumps({"error": "Missing 'bucket' or 'key' in request"}), 400

        print(f"Processing image: s3://{bucket}/{key}")

        # Step 1: Download the image from S3
        image_bytes = download_from_s3(bucket, key)
        print(f"Downloaded {len(image_bytes)} bytes from S3")

        # Step 2: Classify using Vertex AI Gemini
        classification_result = classify_with_gemini(image_bytes, key)
        print(f"Classification result: {classification_result}")

        # Step 3: Send email via Azure Communication Services
        email_sent = send_email(key, classification_result)
        print(f"Email sent: {email_sent}")

        return json.dumps({
            "status": "success",
            "image": key,
            "classification": classification_result,
            "email_sent": email_sent,
        }), 200

    except Exception as e:
        traceback.print_exc()
        return json.dumps({"error": str(e)}), 500


def download_from_s3(bucket: str, key: str) -> bytes:
    """Download an object from S3 and return its bytes."""
    # Retrieve AWS credentials from Secret Manager
    aws_access_key_id = get_secret("imgclass-aws-access-key-id")
    aws_secret_access_key = get_secret("imgclass-aws-secret-access-key")
    
    # Configure boto3 with timeouts and retries
    config = Config(
        connect_timeout=10,
        read_timeout=30,
        retries={'max_attempts': 3, 'mode': 'standard'}
    )
    
    s3_client = boto3.client(
        "s3",
        aws_access_key_id=aws_access_key_id,
        aws_secret_access_key=aws_secret_access_key,
        region_name=AWS_REGION,
        config=config
    )
    
    # Check size first to prevent OOM
    try:
        head = s3_client.head_object(Bucket=bucket, Key=key)
        size = head['ContentLength']
        max_size = 10 * 1024 * 1024  # 10 MB
        
        if size > max_size:
            raise ValueError(f"Image too large: {size} bytes (max {max_size} bytes)")
        
        print(f"Downloading image: {size} bytes")
    except Exception as e:
        print(f"Error checking image size: {e}")
        raise
    
    # Download the image
    response = s3_client.get_object(Bucket=bucket, Key=key)
    return response["Body"].read()


def classify_with_gemini(image_bytes: bytes, filename: str) -> str:
    """
    Send the image to Vertex AI Gemini for classification.
    Returns the classification result as a string.
    """
    vertexai.init(project=GCP_PROJECT_ID, location=GCP_LOCATION)

    # Use stable model version with fallback
    try:
        model = GenerativeModel("gemini-1.5-flash")
    except Exception as e:
        print(f"Error initializing Gemini model: {e}")
        raise RuntimeError("Failed to initialize Gemini model") from e

    # Determine MIME type from filename
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "jpeg"
    mime_map = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp"}
    mime_type = mime_map.get(ext, "image/jpeg")

    image_part = Part.from_data(data=image_bytes, mime_type=mime_type)

    prompt = """Analyze and classify this image. Provide your response in the following format:

**Category:** [Main category of the image]
**Subcategory:** [More specific classification]
**Confidence:** [High/Medium/Low]
**Description:** [A brief 2-3 sentence description of what you see in the image]
**Tags:** [Comma-separated relevant tags]

Be specific and accurate in your classification."""

    try:
        response = model.generate_content([image_part, prompt])
        return response.text
    except Exception as e:
        print(f"Error generating classification: {e}")
        raise RuntimeError("Failed to classify image with Gemini") from e


def send_email(image_name: str, classification: str) -> bool:
    """
    Send classification results via Azure Communication Services Email.
    """
    if not NOTIFICATION_EMAIL:
        print("Email not configured — skipping email send")
        return False

    try:
        # Retrieve Azure credentials from Secret Manager
        azure_email_conn_str = get_secret("imgclass-azure-email-connection-string")
        azure_sender_address = get_secret("imgclass-azure-sender-address")
        
        email_client = EmailClient.from_connection_string(azure_email_conn_str)

        message = {
            "senderAddress": azure_sender_address,
            "recipients": {
                "to": [{"address": NOTIFICATION_EMAIL}]
            },
            "content": {
                "subject": f"Image Classification Result: {image_name}",
                "html": f"""
                <html>
                <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background: #f8fafc;">
                    <div style="background: white; border-radius: 12px; padding: 24px; border: 1px solid #e2e8f0;">
                        <h2 style="color: #1e293b; margin-top: 0;">Image Classification Result</h2>

                        <div style="background: #f1f5f9; border-radius: 8px; padding: 12px; margin-bottom: 16px;">
                            <strong style="color: #64748b; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em;">Image</strong>
                            <p style="margin: 4px 0 0; color: #334155; font-weight: 500;">{image_name}</p>
                        </div>

                        <div style="background: #f1f5f9; border-radius: 8px; padding: 16px; margin-bottom: 16px;">
                            <strong style="color: #64748b; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em;">Classification</strong>
                            <div style="margin-top: 8px; color: #334155; white-space: pre-wrap; line-height: 1.6;">{classification}</div>
                        </div>

                        <div style="border-top: 1px solid #e2e8f0; padding-top: 16px; margin-top: 16px;">
                            <p style="color: #94a3b8; font-size: 12px; margin: 0;">
                                Multi-Cloud Image Classification Pipeline<br/>
                                Storage: AWS S3 &bull; Classification: GCP Vertex AI (Gemini) &bull; Email: Azure Communication Services
                            </p>
                        </div>
                    </div>
                </body>
                </html>
                """,
                "plainText": f"Image: {image_name}\n\nClassification:\n{classification}\n\n---\nMulti-Cloud Image Classification Pipeline",
            },
        }

        poller = email_client.begin_send(message)
        result = poller.result()
        print(f"Email send result: {result}")
        return True

    except Exception as e:
        print(f"Failed to send email: {e}")
        traceback.print_exc()
        return False
