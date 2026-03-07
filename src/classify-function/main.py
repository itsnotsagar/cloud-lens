import hmac
import json
import logging
import os
import re
import time
from html import escape as html_escape

import boto3
import functions_framework
from google.cloud import aiplatform
from azure.communication.email import EmailClient
from botocore.config import Config
from botocore.exceptions import ClientError
from google.cloud import secretmanager
from vertexai.generative_models import GenerativeModel, Part

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


# Environment variables (non-sensitive)
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")
NOTIFICATION_EMAIL = os.environ.get("NOTIFICATION_EMAIL", "")
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "")
GCP_LOCATION = os.environ.get("GCP_LOCATION", "us-central1")
AUTH_TOKEN_SECRET_ID = os.environ.get("AUTH_TOKEN_SECRET_ID", "")

# Secret Manager client (initialized once)
secret_client = secretmanager.SecretManagerServiceClient()

# Cache for secrets and clients (avoid repeated API calls and initialization)
_secrets_cache = {}
_s3_client = None
_email_client = None
_gemini_model = None

# Validate required environment variables at startup
REQUIRED_ENV_VARS = [
    "S3_BUCKET_NAME",
    "AWS_REGION",
    "NOTIFICATION_EMAIL",
    "GCP_PROJECT_ID",
    "GCP_LOCATION",
    "AUTH_TOKEN_SECRET_ID"
]

def validate_environment():
    """Validate all required environment variables are set."""
    missing = [var for var in REQUIRED_ENV_VARS if not os.environ.get(var)]
    if missing:
        raise RuntimeError(f"Missing required environment variables: {', '.join(missing)}")

# Validate at module load time
validate_environment()

# Allowed image extensions
ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png", "webp"}

def _is_valid_s3_key(key: str) -> bool:
    """Validate S3 key to prevent path traversal and restrict to image files."""
    if not key or ".." in key or key.startswith("/"):
        return False
    # Must end with an allowed image extension
    ext = key.rsplit(".", 1)[-1].lower() if "." in key else ""
    if ext not in ALLOWED_EXTENSIONS:
        return False
    # Only allow safe characters in the key
    if not re.match(r'^[\w./ -]+$', key):
        return False
    return True


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
        logger.error("Failed to retrieve secret: %s", e)
        raise RuntimeError("Failed to retrieve required secret") from e


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
        expected_token = get_secret(AUTH_TOKEN_SECRET_ID)
        if not auth_header or not hmac.compare_digest(auth_header, expected_token):
            logger.warning("Unauthorized access attempt")
            return json.dumps({"error": "Unauthorized"}), 401
        # Parse the incoming request
        request_json = request.get_json(silent=True)
        if not request_json:
            return json.dumps({"error": "No JSON payload received"}), 400

        # Always use the configured bucket — never allow caller to override
        bucket = S3_BUCKET_NAME
        key = request_json.get("key", "")

        if not key:
            return json.dumps({"error": "Missing 'key' in request"}), 400

        # Validate S3 key to prevent path traversal or access to unintended objects
        if not _is_valid_s3_key(key):
            return json.dumps({"error": "Invalid image key"}), 400

        logger.info("Processing image: s3://%s/%s", bucket, key)

        # Step 1: Download the image from S3
        image_bytes = download_from_s3(bucket, key)

        # Step 2: Classify using Vertex AI Gemini
        classification_result = classify_with_gemini(image_bytes, key)
        logger.info("Classification complete for %s (%d chars)", key, len(classification_result))

        # Step 3: Send email via Azure Communication Services
        email_sent = send_email(key, classification_result)
        logger.info("Email sent: %s", email_sent)

        return json.dumps({
            "status": "success",
            "image": key,
            "classification": classification_result,
            "email_sent": email_sent,
        }), 200

    except Exception as e:
        logger.exception("Unhandled error processing request")
        return json.dumps({"error": "Internal server error"}), 500


def get_s3_client():
    """Get or create cached S3 client."""
    global _s3_client
    if _s3_client is None:
        aws_access_key_id = get_secret("imgclass-aws-access-key-id")
        aws_secret_access_key = get_secret("imgclass-aws-secret-access-key")
        
        config = Config(
            connect_timeout=10,
            read_timeout=30,
            retries={'max_attempts': 3, 'mode': 'standard'}
        )
        
        _s3_client = boto3.client(
            "s3",
            aws_access_key_id=aws_access_key_id,
            aws_secret_access_key=aws_secret_access_key,
            region_name=AWS_REGION,
            config=config
        )
    return _s3_client


def download_from_s3(bucket: str, key: str) -> bytes:
    """Download an object from S3 and return its bytes."""
    s3_client = get_s3_client()
    
    # Retry logic for eventual consistency (S3 might not be immediately available)
    max_retries = 2
    retry_delay = 0.5  # seconds
    
    for attempt in range(max_retries):
        try:
            # Download directly without head request (saves one API call)
            response = s3_client.get_object(Bucket=bucket, Key=key)
            image_bytes = response["Body"].read()
            
            # Validate size after download
            size = len(image_bytes)
            max_size = 10 * 1024 * 1024  # 10 MB
            
            if size > max_size:
                raise ValueError(f"Image too large: {size} bytes (max {max_size} bytes)")
            
            logger.info("Downloaded %d bytes from S3", size)
            return image_bytes
            
        except s3_client.exceptions.NoSuchKey:
            if attempt < max_retries - 1:
                logger.info("Image not yet available, retrying in %ss (attempt %d/%d)", retry_delay, attempt + 1, max_retries)
                time.sleep(retry_delay)
                retry_delay *= 2  # Exponential backoff
            else:
                logger.error("Image not found after %d attempts", max_retries)
                raise
        except ClientError as e:
            logger.error("S3 client error downloading image: %s", e.response['Error']['Code'])
            raise
        except Exception as e:
            logger.error("Error downloading image: %s", e)
            raise


def get_gemini_model():
    """Get or create cached Gemini model."""
    global _gemini_model
    if _gemini_model is None:
        aiplatform.init(project=GCP_PROJECT_ID, location=GCP_LOCATION)
        _gemini_model = GenerativeModel(
            "gemini-2.5-flash",
            generation_config={
                "temperature": 0.4,
                "max_output_tokens": 512,
            }
        )
    return _gemini_model


def classify_with_gemini(image_bytes: bytes, filename: str) -> str:
    """
    Send the image to Vertex AI Gemini for classification.
    Returns the classification result as a string.
    """
    # Determine MIME type from filename
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else "jpeg"
    mime_map = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp"}
    mime_type = mime_map.get(ext, "image/jpeg")

    image_part = Part.from_data(data=image_bytes, mime_type=mime_type)

    prompt = """Classify this image with:
**Category:** [main category]
**Subcategory:** [specific type]
**Confidence:** [High/Medium/Low]
**Description:** [2-3 sentences]
**Tags:** [comma-separated tags]"""

    model = get_gemini_model()
    response = model.generate_content(
        [image_part, prompt],
    )
    return response.text


def get_email_client():
    """Get or create cached email client."""
    global _email_client
    if _email_client is None:
        azure_email_conn_str = get_secret("imgclass-azure-email-connection-string")
        _email_client = EmailClient.from_connection_string(azure_email_conn_str)
    return _email_client


def send_email(image_name: str, classification: str) -> bool:
    """
    Send classification results via Azure Communication Services Email.
    """
    if not NOTIFICATION_EMAIL:
        logger.info("Email not configured — skipping email send")
        return False

    try:
        azure_sender_address = get_secret("imgclass-azure-sender-address")
        email_client = get_email_client()

        # Escape user-controlled content to prevent HTML injection
        safe_image_name = html_escape(image_name)
        safe_classification = html_escape(classification)

        message = {
            "senderAddress": azure_sender_address,
            "recipients": {
                "to": [{"address": NOTIFICATION_EMAIL}]
            },
            "content": {
                "subject": f"Image Classification: {safe_image_name}",
                "html": f"""<html><body style="font-family:sans-serif;max-width:600px;margin:0 auto;padding:20px">
<h2>Image Classification Result</h2>
<div style="background:#f5f5f5;padding:15px;border-radius:8px;margin:15px 0">
<strong>Image:</strong> {safe_image_name}
</div>
<div style="background:#f5f5f5;padding:15px;border-radius:8px;margin:15px 0">
<strong>Classification:</strong><br><pre style="white-space:pre-wrap;margin:10px 0">{safe_classification}</pre>
</div>
<p style="color:#666;font-size:12px;margin-top:20px">Multi-Cloud Pipeline: AWS S3 &rarr; GCP Vertex AI &rarr; Azure Email</p>
</body></html>""",
                "plainText": f"Image: {image_name}\n\nClassification:\n{classification}\n\n---\nMulti-Cloud Image Classification Pipeline",
            },
        }

        poller = email_client.begin_send(message)
        result = poller.result(timeout=30)
        logger.info("Email sent successfully")
        return True

    except Exception as e:
        logger.exception("Failed to send email")
        return False
