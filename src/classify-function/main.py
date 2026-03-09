import hmac
import json
import logging
import os
import re
import time
from datetime import datetime, timedelta, timezone
from html import escape as html_escape
from urllib.request import Request, urlopen

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
AWS_ROLE_ARN = os.environ.get("AWS_ROLE_ARN", "")
NOTIFICATION_EMAIL = os.environ.get("NOTIFICATION_EMAIL", "")
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "")
GCP_LOCATION = os.environ.get("GCP_LOCATION", "us-central1")
AUTH_TOKEN_SECRET_ID = os.environ.get("AUTH_TOKEN_SECRET_ID", "")
AZURE_EMAIL_CONN_SECRET_ID = os.environ.get("AZURE_EMAIL_CONN_SECRET_ID", "")
AZURE_SENDER_SECRET_ID = os.environ.get("AZURE_SENDER_SECRET_ID", "")

# Secret Manager client (initialized once)
secret_client = secretmanager.SecretManagerServiceClient()

# Cache for secrets and clients (avoid repeated API calls and initialization)
_secrets_cache = {}
_s3_client = None
_s3_credentials_expiry = None
_email_client = None
_gemini_model = None
_processed_images = {}  # Cache to prevent duplicate processing

# Validate required environment variables at startup
REQUIRED_ENV_VARS = [
    "S3_BUCKET_NAME",
    "AWS_REGION",
    "AWS_ROLE_ARN",
    "NOTIFICATION_EMAIL",
    "GCP_PROJECT_ID",
    "GCP_LOCATION",
    "AUTH_TOKEN_SECRET_ID",
    "AZURE_EMAIL_CONN_SECRET_ID",
    "AZURE_SENDER_SECRET_ID"
]

def validate_environment():
    """Validate all required environment variables are set."""
    missing = [var for var in REQUIRED_ENV_VARS if not os.environ.get(var)]
    if missing:
        raise RuntimeError(f"Missing required environment variables: {', '.join(missing)}")
    # Validate email format
    email_pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    if NOTIFICATION_EMAIL and not re.match(email_pattern, NOTIFICATION_EMAIL):
        raise RuntimeError(f"Invalid NOTIFICATION_EMAIL format: {NOTIFICATION_EMAIL}")

# Validate at module load time
validate_environment()

# Allowed image extensions and their magic bytes
ALLOWED_EXTENSIONS = {"jpg", "jpeg", "png", "webp"}
IMAGE_MAGIC_BYTES = {
    b"\xff\xd8\xff": "jpeg",
    b"\x89PNG": "png",
    b"RIFF": "webp",  # WebP starts with RIFF....WEBP
}
MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10 MB
MAX_CLASSIFICATION_LENGTH = 2000
CACHE_MAX_AGE_SECONDS = 300  # 5 minutes

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

        # Deduplication: Check if we've processed this image recently (within 60 seconds)
        image_id = f"{bucket}/{key}"
        current_time = time.time()
        
        if image_id in _processed_images:
            last_processed = _processed_images[image_id]
            if current_time - last_processed < 60:
                logger.info("Skipping duplicate request for %s (processed %.1fs ago)", image_id, current_time - last_processed)
                return json.dumps({
                    "status": "skipped",
                    "reason": "duplicate_request",
                    "image": key,
                }), 200
        
        # Mark as processing
        _processed_images[image_id] = current_time
        
        # Clean up entries older than CACHE_MAX_AGE_SECONDS
        expired = [k for k, v in _processed_images.items() if current_time - v > CACHE_MAX_AGE_SECONDS]
        for k in expired:
            del _processed_images[k]

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


def _get_google_id_token(audience: str) -> str:
    """Fetch a Google-signed OIDC identity token from the metadata server."""
    url = (
        "http://metadata.google.internal/computeMetadata/v1/"
        f"instance/service-accounts/default/identity?audience={audience}&format=full"
    )
    req = Request(url, headers={"Metadata-Flavor": "Google"})
    with urlopen(req, timeout=5) as resp:
        return resp.read().decode("utf-8")


def get_s3_client():
    """Get or create cached S3 client using Workload Identity Federation."""
    global _s3_client, _s3_credentials_expiry

    # Reuse cached client if credentials haven't expired (with 60s buffer)
    if _s3_client is not None and _s3_credentials_expiry is not None:
        if datetime.now(timezone.utc) < _s3_credentials_expiry:
            return _s3_client

    # Get Google OIDC token and exchange for AWS temporary credentials
    google_token = _get_google_id_token("sts.amazonaws.com")

    sts_client = boto3.client("sts", region_name=AWS_REGION)
    response = sts_client.assume_role_with_web_identity(
        RoleArn=AWS_ROLE_ARN,
        RoleSessionName="classify-function",
        WebIdentityToken=google_token,
        DurationSeconds=900,
    )

    creds = response["Credentials"]
    _s3_credentials_expiry = creds["Expiration"].replace(tzinfo=timezone.utc) - timedelta(seconds=60)

    config = Config(
        connect_timeout=10,
        read_timeout=30,
        retries={"max_attempts": 3, "mode": "standard"},
    )

    _s3_client = boto3.client(
        "s3",
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
        region_name=AWS_REGION,
        config=config,
    )
    return _s3_client


def _validate_image_magic_bytes(image_bytes: bytes) -> bool:
    """Validate that the file content matches a known image format via magic bytes."""
    for magic, _ in IMAGE_MAGIC_BYTES.items():
        if image_bytes[:len(magic)] == magic:
            return True
    return False


def download_from_s3(bucket: str, key: str) -> bytes:
    """Download an object from S3 and return its bytes."""
    s3_client = get_s3_client()
    
    # Retry logic for eventual consistency (S3 might not be immediately available)
    max_retries = 2
    retry_delay = 0.5  # seconds
    
    for attempt in range(max_retries):
        try:
            # Check size before downloading to prevent memory exhaustion
            head = s3_client.head_object(Bucket=bucket, Key=key)
            content_length = head.get("ContentLength", 0)
            if content_length > MAX_IMAGE_SIZE:
                raise ValueError(f"Image too large: {content_length} bytes (max {MAX_IMAGE_SIZE} bytes)")

            response = s3_client.get_object(Bucket=bucket, Key=key)
            image_bytes = response["Body"].read()

            # Validate magic bytes to ensure it's actually an image
            if not _validate_image_magic_bytes(image_bytes):
                raise ValueError("File content does not match a supported image format")
            
            logger.info("Downloaded %d bytes from S3", len(image_bytes))
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
    result = response.text
    if len(result) > MAX_CLASSIFICATION_LENGTH:
        result = result[:MAX_CLASSIFICATION_LENGTH] + "..."
    return result


def get_email_client():
    """Get or create cached email client."""
    global _email_client
    if _email_client is None:
        azure_email_conn_str = get_secret(AZURE_EMAIL_CONN_SECRET_ID)
        _email_client = EmailClient.from_connection_string(azure_email_conn_str)
    return _email_client


def _parse_classification(text: str) -> dict:
    """Parse the Gemini classification response into structured fields."""
    fields = {}
    current_key = None
    current_value = []

    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue
        # Match lines like "**Category:** Animals" or "Category: Animals"
        match = re.match(r'\*{0,2}(Category|Subcategory|Confidence|Description|Tags)\s*:\s*\*{0,2}\s*(.*)', line, re.IGNORECASE)
        if match:
            if current_key:
                fields[current_key] = " ".join(current_value).strip()
            current_key = match.group(1).lower()
            current_value = [match.group(2).strip()]
        elif current_key:
            current_value.append(line)

    if current_key:
        fields[current_key] = " ".join(current_value).strip()

    return fields


def _build_email_html(safe_image_name: str, safe_classification: str) -> str:
    """Build a styled HTML email from the classification result."""
    fields = _parse_classification(safe_classification)

    confidence = fields.get("confidence", "")
    confidence_colors = {
        "high": ("#059669", "#d1fae5"),
        "medium": ("#d97706", "#fef3c7"),
        "low": ("#dc2626", "#fee2e2"),
    }
    conf_fg, conf_bg = confidence_colors.get(confidence.lower(), ("#6b7280", "#f3f4f6"))

    tags_html = ""
    if "tags" in fields:
        tags = [t.strip() for t in fields["tags"].split(",") if t.strip()]
        tags_html = " ".join(
            f'<span style="display:inline-block;background:#e0e7ff;color:#3730a3;'
            f'padding:4px 10px;border-radius:12px;font-size:12px;margin:3px 2px">{t}</span>'
            for t in tags
        )

    # Build rows for category, subcategory, description
    detail_rows = ""
    for key, label, icon in [
        ("category", "Category", "\U0001f4c2"),
        ("subcategory", "Subcategory", "\U0001f50d"),
        ("description", "Description", "\U0001f4dd"),
    ]:
        if key in fields:
            detail_rows += (
                f'<tr><td style="padding:10px 12px;color:#6b7280;font-size:13px;'
                f'vertical-align:top;white-space:nowrap">{icon} {label}</td>'
                f'<td style="padding:10px 12px;color:#1f2937;font-size:14px">{fields[key]}</td></tr>'
            )

    confidence_badge = ""
    if confidence:
        confidence_badge = (
            f'<tr><td style="padding:10px 12px;color:#6b7280;font-size:13px;vertical-align:top">'
            f'\u2705 Confidence</td><td style="padding:10px 12px">'
            f'<span style="display:inline-block;background:{conf_bg};color:{conf_fg};'
            f'padding:3px 12px;border-radius:10px;font-size:13px;font-weight:600">'
            f'{confidence}</span></td></tr>'
        )

    return f"""<html>
<body style="margin:0;padding:0;background:#f3f4f6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif">
<div style="max-width:560px;margin:30px auto;background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.1)">
  <div style="background:linear-gradient(135deg,#4f46e5,#7c3aed);padding:28px 24px;text-align:center">
    <h1 style="margin:0;color:#ffffff;font-size:20px;font-weight:600">Image Classification Result</h1>
  </div>
  <div style="padding:24px">
    <div style="background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:14px 16px;margin-bottom:20px;display:flex;align-items:center">
      <span style="font-size:18px;margin-right:10px">\U0001f5bc\ufe0f</span>
      <div>
        <div style="font-size:11px;color:#9ca3af;text-transform:uppercase;letter-spacing:0.5px">Image</div>
        <div style="font-size:14px;color:#1f2937;font-weight:500;word-break:break-all">{safe_image_name}</div>
      </div>
    </div>
    <table style="width:100%;border-collapse:collapse;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;overflow:hidden">
      {detail_rows}
      {confidence_badge}
    </table>
    {"<div style='margin-top:16px'><div style=font-size:13px;color:#6b7280;margin-bottom:6px>🏷️ Tags</div>" + tags_html + "</div>" if tags_html else ""}
  </div>
  <div style="border-top:1px solid #e5e7eb;padding:16px 24px;text-align:center">
    <span style="font-size:11px;color:#9ca3af">AWS S3 &rarr; GCP Vertex AI &rarr; Azure Email</span>
  </div>
</div>
</body></html>"""


def send_email(image_name: str, classification: str) -> bool:
    """
    Send classification results via Azure Communication Services Email.
    """
    if not NOTIFICATION_EMAIL:
        logger.info("Email not configured — skipping email send")
        return False

    try:
        azure_sender_address = get_secret(AZURE_SENDER_SECRET_ID)
        email_client = get_email_client()

        # Escape user-controlled content to prevent HTML injection
        safe_image_name = html_escape(image_name)
        safe_classification = html_escape(classification)

        # Parse classification fields for structured rendering
        html_body = _build_email_html(safe_image_name, safe_classification)

        message = {
            "senderAddress": azure_sender_address,
            "recipients": {
                "to": [{"address": NOTIFICATION_EMAIL}]
            },
            "content": {
                "subject": f"Image Classification: {safe_image_name}",
                "html": html_body,
                "plainText": f"Image: {image_name}\n\nClassification:\n{classification}\n\n---\nMulti-Cloud Image Classification Pipeline",
            },
        }

        # Retry with exponential backoff for transient failures
        last_error = None
        for attempt in range(3):
            try:
                poller = email_client.begin_send(message)
                poller.result(timeout=30)
                logger.info("Email sent successfully")
                return True
            except Exception as e:
                last_error = e
                if attempt < 2:
                    wait = 2 ** attempt
                    logger.warning("Email send attempt %d failed, retrying in %ds: %s", attempt + 1, wait, e)
                    time.sleep(wait)

        logger.exception("Failed to send email after 3 attempts: %s", last_error)
        return False

    except Exception as e:
        logger.exception("Failed to prepare email")
        return False
