import json
import os
import urllib.request
import urllib.parse
import urllib.error

"""
Lambda Relay — receives S3 event notifications and forwards them
to the GCP Cloud Function for image classification.
"""

GCP_FUNCTION_URL = os.environ.get("GCP_FUNCTION_URL", "")


def handler(event, context):
    if not GCP_FUNCTION_URL:
        print("ERROR: GCP_FUNCTION_URL environment variable is not set")
        return {"statusCode": 500, "body": "Missing GCP_FUNCTION_URL"}

    print(f"Received S3 event: {json.dumps(event, indent=2)}")

    results = []

    for record in event.get("Records", []):
        bucket = record.get("s3", {}).get("bucket", {}).get("name", "")
        key = urllib.parse.unquote_plus(
            record.get("s3", {}).get("object", {}).get("key", "")
        )
        size = record.get("s3", {}).get("object", {}).get("size")
        event_name = record.get("eventName", "")

        if not bucket or not key:
            print(f"Skipping record — missing bucket or key: {record}")
            continue

        print(f"Processing: s3://{bucket}/{key} (event: {event_name}, size: {size})")

        payload = json.dumps({
            "bucket": bucket,
            "key": key,
            "size": size,
            "event": event_name,
            "timestamp": record.get("eventTime"),
        }).encode("utf-8")

        try:
            response = post_to_gcp(payload)
            print(f"GCP response for {key}: {response['status']} — {response['body']}")
            results.append({"key": key, "status": response["status"], "body": response["body"]})
        except Exception as e:
            print(f"Error relaying {key} to GCP: {e}")
            results.append({"key": key, "status": "error", "error": str(e)})

    return {
        "statusCode": 200,
        "body": json.dumps({"processed": len(results), "results": results}),
    }


def post_to_gcp(payload: bytes) -> dict:
    """POST JSON payload to the GCP Cloud Function URL."""
    req = urllib.request.Request(
        GCP_FUNCTION_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            body = resp.read().decode("utf-8")
            return {"status": resp.status, "body": body}
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8") if e.fp else ""
        return {"status": e.code, "body": body}
