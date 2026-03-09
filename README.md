# Multi-Cloud Image Classification Pipeline

An end-to-end image classification pipeline deployed across **AWS**, **GCP**, and **Azure** using Terraform & GitHub Actions.

## Architecture

```
Browser → CloudFront (HTTPS) → S3 Static Site (AWS)
  ↓ PUT image via API Gateway
S3 Bucket (AWS) [1-day retention]
  ↓ S3 event notification
EventBridge Rule (AWS) → API Destination [authenticated]
  ↓ HTTP POST with auth token
Cloud Function (GCP) [auth token validated in code]
  ↓ Gets Google OIDC token → AWS STS AssumeRoleWithWebIdentity
  ↓ Downloads image from S3 (temporary credentials via WIF)
  ↓ Classifies via Vertex AI Gemini 2.5 Flash
  ↓ Sends email via
Azure Communication Services → Recipient Inbox
```

**Supported image formats:** PNG, JPG, WEBP (max 10 MB)

### Cloud Responsibilities

| Cloud | Role | Services |
|-------|------|----------|
| **AWS** | Storage, CDN, event routing | S3, API Gateway, EventBridge, CloudFront |
| **GCP** | AI classification, secrets management | Cloud Functions (2nd gen), Vertex AI Gemini, Secret Manager |
| **Azure** | Email delivery | Communication Services |

### Security Features

- **HTTPS via CloudFront**: Website served over HTTPS with security response headers (HSTS, X-Frame-Options DENY, X-Content-Type-Options)
- **Workload Identity Federation**: GCP Cloud Function obtains temporary AWS credentials via OIDC → STS (no stored AWS keys)
- **Centralized Secrets**: All credentials stored in GCP Secret Manager
- **Auto-delete Images**: S3 lifecycle policy removes images after 1 day
- **Authenticated Event Routing**: EventBridge uses API key authentication
- **Input Validation**: File type, size, magic bytes, and S3 key validation
- **HTML Escape**: All user content escaped before email rendering

## Prerequisites

1. **AWS** — IAM user with programmatic access (access key + secret)
2. **GCP** — Service account with roles: Cloud Functions Admin, Vertex AI User, Storage Admin, IAM Service Account Admin
3. **Azure** — Service Principal (SPN) with Contributor role on a subscription

## Setup

### 1. Configure GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS IAM access key |
| `AWS_SECRET_ACCESS_KEY` | AWS IAM secret key |
| `GCP_SERVICE_ACCOUNT_KEY` | Base64-encoded GCP service account JSON (`base64 -i key.json`) |
| `ARM_CLIENT_ID` | Azure SPN application (client) ID |
| `ARM_CLIENT_SECRET` | Azure SPN client secret |
| `ARM_TENANT_ID` | Azure AD tenant ID |
| `ARM_SUBSCRIPTION_ID` | Azure subscription ID |

### 2. Configure GitHub Variables

Go to **Settings → Secrets and variables → Actions → Variables** and add:

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_PREFIX` | `imgclass` | Prefix for all resource names |
| `NOTIFICATION_EMAIL` | — | Email to receive classification results |
| `GCP_PROJECT_ID` | — | Your GCP project ID |
| `AWS_REGION` | `us-east-1` | AWS deployment region |
| `GCP_REGION` | `us-central1` | GCP deployment region |
| `AZURE_LOCATION` | `eastus` | Azure deployment region |

### 3. Bootstrap State Backends

Run the **Bootstrap State Backends** workflow once (manually via `workflow_dispatch`) to create:
- AWS: S3 bucket + DynamoDB table for Terraform state
- GCP: GCS bucket for Terraform state
- Azure: Storage account + container for Terraform state

### 4. Deploy

Push to `main` or run the **Deploy Multi-Cloud Image Classification** workflow manually.

The workflow deploys in this order:
1. **Azure** (email service) + **AWS Initial** (storage, website, EventBridge with placeholders) — in parallel
2. **GCP** (classification function + secrets) — needs outputs from step 1
3. **AWS Final** (update EventBridge with real GCP function URL) — needs GCP outputs

## Project Structure

```
.
├── .github/workflows/
│   ├── deploy.yml                  # Main deployment pipeline
│   ├── destroy.yml                 # Infrastructure teardown
│   ├── setup-state-backends.yml    # Bootstrap Terraform state backends
│   └── cleanup-state-backends.yml  # Remove state backends
├── terraform/
│   ├── aws/                        # S3, API Gateway, EventBridge, CloudFront, IAM
│   ├── gcp/                        # Cloud Function, Secret Manager, Vertex AI, IAM
│   ├── azure/                      # Communication Services for email
│   └── README.md
├── src/
│   ├── frontend/
│   │   ├── index.html              # Upload UI (deployed to S3 via CloudFront)
│   │   └── styles.css
│   └── classify-function/
│       ├── main.py                 # Classification + email logic
│       └── requirements.txt
└── README.md
```

## How It Works

1. User opens the website served via **CloudFront** (HTTPS) → **S3** (AWS)
2. Selects an image (PNG, JPG, or WEBP, max 10 MB) and clicks **Upload & Classify**
3. JavaScript PUTs the image to **API Gateway** → **S3** (AWS)
4. S3 event triggers **EventBridge** rule (AWS)
5. EventBridge sends authenticated POST to **Cloud Function** (GCP)
6. Cloud Function:
   - Validates authentication token
   - Obtains temporary AWS credentials via **Workload Identity Federation** (OIDC → STS)
   - Downloads the image from S3
   - Classifies with **Vertex AI Gemini 2.5 Flash**
   - Sends styled email with results via **Azure Communication Services**
7. Image is automatically deleted from S3 after 1 day

## Tear Down

Run the destroy workflow to remove all resources.

Destroy order (handled automatically):
1. AWS (all resources: S3, API Gateway, EventBridge)
2. GCP (Cloud Function + Secret Manager secrets)
3. Azure (Communication Services)

**Note:** State backends must be destroyed separately if needed.

## Cost Estimate

All services used fall within free tiers for demo/testing:
- **AWS:** S3 free tier, API Gateway 1M free calls/month, EventBridge 14M free events/month
- **GCP:** Cloud Functions 2M free invocations/month, Secret Manager 6 active secrets free, Vertex AI pay-per-use
- **Azure:** Communication Services free tier includes email

**Cost Optimizations:**
- Images auto-delete after 1 day (reduces S3 storage)
- CloudWatch logs retained for 7 days only
- EventBridge used instead of Lambda (no compute costs for relay)

## Limitations & Security Notes

- API Gateway has a 10 MB payload limit (fine for most images)
- Azure Communication Services sends from `donotreply@<id>.azurecomm.net` — no custom domain
- GCP Cloud Function cold starts may add 3-5s on first invocation
- Images are automatically deleted after 1 day
- GCP Function requires authentication token (not publicly accessible)
- AWS credentials used by GCP function are restricted to S3 read-only access

**Production Recommendations:**
- Use Workload Identity Federation instead of service account keys
- Add rate limiting on API Gateway
- Restrict CORS origins to your domain
- Enable CloudTrail and Cloud Audit Logs
- Use custom domain for Azure email
