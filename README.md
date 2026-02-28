# Multi-Cloud Image Classification Pipeline

An end-to-end image classification pipeline deployed across **AWS**, **GCP**, and **Azure** using Terraform & GitHub Actions.

## Architecture

```
Browser → S3 Static Site (AWS)
  ↓ PUT image via API Gateway
S3 Bucket (AWS) [1-day retention]
  ↓ S3 event notification
EventBridge Rule (AWS) → API Destination [authenticated]
  ↓ HTTP POST with auth token
Cloud Function (GCP) [private, auth required]
  ↓ Reads secrets from GCP Secret Manager
  ↓ Downloads image from S3 (restricted credentials)
  ↓ Classifies via Vertex AI Gemini
  ↓ Sends email via
Azure Communication Services → Recipient Inbox
```

### Cloud Responsibilities

| Cloud | Role | Services |
|-------|------|----------|
| **AWS** | Storage, website, event routing | S3, API Gateway, EventBridge |
| **GCP** | AI classification, secrets management | Cloud Functions (2nd gen), Vertex AI Gemini, Secret Manager |
| **Azure** | Email delivery | Communication Services |

### Security Features

- **Private GCP Function**: Requires authentication token (no public access)
- **Restricted AWS Credentials**: IAM user with S3 read-only access
- **Centralized Secrets**: All credentials stored in GCP Secret Manager
- **Auto-delete Images**: S3 lifecycle policy removes images after 1 day
- **Authenticated Event Routing**: EventBridge uses API key authentication

## Prerequisites

1. **AWS** — IAM user with programmatic access (access key + secret)
2. **GCP** — Service account with roles: Cloud Functions Admin, Vertex AI User, Storage Admin
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
│   ├── deploy.yml             # Main deployment pipeline
│   └── destroy.yml            # Infrastructure teardown
├── terraform/
│   ├── aws/                   # All AWS resources (S3, API Gateway, EventBridge)
│   ├── gcp/                   # All GCP resources (Cloud Function, Secrets, Vertex AI)
│   ├── azure/                 # Azure Communication Services for email
│   └── README.md              # Detailed deployment instructions
├── src/
│   ├── frontend/
│   │   ├── index.html         # Upload page (deployed to S3)
│   │   └── styles.css         # Stylesheet
│   └── classify-function/     # Python Cloud Function
│       ├── main.py            # Classification + email logic
│       └── requirements.txt
├── WORKFLOW_UPDATES.md        # GitHub Actions configuration guide
├── TERRAFORM_REORGANIZATION.md # Infrastructure restructuring details
└── README.md
```

## How It Works

1. User opens the static website hosted on **S3** (AWS)
2. Selects an image and clicks **Upload & Classify**
3. JavaScript PUTs the image to **API Gateway** → **S3** (AWS)
4. S3 event triggers **EventBridge** rule (AWS)
5. EventBridge sends authenticated POST to **Cloud Function** (GCP)
6. Cloud Function:
   - Validates authentication token
   - Retrieves AWS credentials from **Secret Manager** (GCP)
   - Downloads the image from S3 using restricted credentials
   - Sends it to **Vertex AI Gemini** for classification
   - Retrieves Azure credentials from **Secret Manager** (GCP)
   - Emails results via **Azure Communication Services**
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
