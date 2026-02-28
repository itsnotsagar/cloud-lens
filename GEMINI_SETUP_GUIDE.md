# Gemini Model Setup Guide

## Issue
All Gemini models are returning 404 errors, indicating the project doesn't have access to them.

## Root Cause
You need to accept the Vertex AI Generative AI terms and enable the models in your GCP project.

## Solution Steps

### 1. Accept Vertex AI Generative AI Terms
Visit this URL and accept the terms:
```
https://console.cloud.google.com/vertex-ai/generative/language?project=gcp-vit
```

Or navigate manually:
1. Go to GCP Console: https://console.cloud.google.com
2. Select project: `gcp-vit`
3. Navigate to: Vertex AI → Generative AI → Language
4. Accept the terms of service when prompted

### 2. Verify API is Enabled
The API is already enabled (confirmed from your logs), but verify:
```bash
gcloud services list --enabled --project=gcp-vit | grep aiplatform
```

Should show: `aiplatform.googleapis.com`

### 3. Test Model Access
After accepting terms, test if models are accessible:
```bash
gcloud ai models list \
  --region=us-central1 \
  --project=gcp-vit \
  --filter="displayName:gemini"
```

### 4. Redeploy the Function
After accepting terms, redeploy:
```bash
cd terraform/gcp
terraform apply -auto-approve
```

### 5. Test the Pipeline
Upload an image to S3 to trigger the pipeline:
```bash
aws s3 cp test-image.jpg s3://imgclass-images-574143645535/
```

### 6. Check Logs
Monitor the function logs:
```bash
gcloud functions logs read imgclass-classify \
  --region=us-central1 \
  --project=gcp-vit \
  --limit=20 \
  --format="table(time_utc, log)"
```

## Updated Model Fallback Chain
The code now tries these models in order:
1. `gemini-1.5-flash` - Most stable and widely available
2. `gemini-1.5-pro` - Pro version fallback
3. `gemini-1.5-flash-001` - Specific version
4. `gemini-1.0-pro-vision` - Legacy vision model

## Expected Behavior
- Function should successfully classify with one of the models
- Email should be sent to: `sagar.yadav2019@gmail.com`
- Check spam folder for emails from: `donotreply@*.azurecomm.net`

## Troubleshooting
If models still fail after accepting terms:
1. Try a different region (e.g., `us-east1`, `europe-west1`)
2. Wait 5-10 minutes for terms acceptance to propagate
3. Verify service account has `roles/aiplatform.user` role
4. Check quota limits in GCP Console
