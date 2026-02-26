import base64
import json
import os
import traceback

import boto3
import functions_framework
import vertexai
from azure.communication.email import EmailClient
from google.cloud import aiplatform
from vertexai.generative_models import GenerativeModel, Image, Part


# Environment variables
AWS_ACCESS_KEY_ID = os.environ.get("AWS_ACCESS_KEY_ID_VALUE", "")
AWS_SECRET_ACCESS_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY_VALUE", "")
AWS_REGION = os.environ.get("AWS_REGION_VALUE", "us-east-1")
S3_BUCKET_NAME = os.environ.get("S3_BUCKET_NAME", "")
AZURE_EMAIL_CONN_STR = os.environ.get("AZURE_EMAIL_CONNECTION_STR", "")
AZURE_SENDER_ADDRESS = os.environ.get("AZURE_SENDER_ADDRESS", "")
NOTIFICATION_EMAIL = os.environ.get("NOTIFICATION_EMAIL", "")
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "")
GCP_LOCATION = os.environ.get("GCP_LOCATION", "us-central1")


@functions_framework.http
def classify_image(request):
    """
    HTTP Cloud Function that:
    1. Downloads an image from S3
    2. Classifies it using Vertex AI Gemini
    3. Sends the results via Azure Communication Services email
    """
    try:
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
    s3_client = boto3.client(
        "s3",
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
        region_name=AWS_REGION,
    )
    response = s3_client.get_object(Bucket=bucket, Key=key)
    return response["Body"].read()


def classify_with_gemini(image_bytes: bytes, filename: str) -> str:
    """
    Send the image to Vertex AI Gemini for classification.
    Returns the classification result as a string.
    """
    vertexai.init(project=GCP_PROJECT_ID, location=GCP_LOCATION)

    model = GenerativeModel("gemini-2.0-flash")

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

    response = model.generate_content([image_part, prompt])

    return response.text


def send_email(image_name: str, classification: str) -> bool:
    """
    Send classification results via Azure Communication Services Email.
    """
    if not AZURE_EMAIL_CONN_STR or not NOTIFICATION_EMAIL:
        print("Email not configured — skipping email send")
        return False

    try:
        email_client = EmailClient.from_connection_string(AZURE_EMAIL_CONN_STR)

        message = {
            "senderAddress": AZURE_SENDER_ADDRESS,
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
