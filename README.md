# Multi-Cloud Image Classification Pipeline

An end-to-end image classification pipeline deployed across **AWS**, **GCP**, and **Azure** using Terraform & GitHub Actions.

## Architecture

```
Browser → S3 Static Site (AWS)
  ↓ PUT image via API Gateway
S3 Bucket (AWS)
  ↓ S3 event notification
Lambda Relay (AWS) → HTTP POST → Cloud Function (GCP)
  ↓ Downloads image from S3
  ↓ Classifies via Vertex AI Gemini
  ↓ Sends email via
Azure Communication Services → Recipient Inbox
```

### Cloud Responsibilities

| Cloud | Role | Services |
|-------|------|----------|
| **AWS** | Storage, website, event routing | S3, API Gateway, Lambda |
| **GCP** | AI classification | Cloud Functions (2nd gen), Vertex AI Gemini |
| **Azure** | Email delivery | Communication Services |

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
1. **Azure** (email service) + **AWS Core** (storage, website) — in parallel
2. **GCP** (classification function) — needs outputs from step 1
3. **AWS Trigger** (Lambda relay + S3 notification) — needs GCP function URL

## Project Structure

```
.
├── .github/workflows/
│   ├── bootstrap.yml          # One-time: create state backends
│   └── deploy.yml             # Main deployment pipeline
├── terraform/
│   ├── bootstrap/             # State backend resources (local state)
│   ├── azure/                 # Communication Services for email
│   ├── aws-core/              # S3 + API Gateway + static website
│   ├── aws-trigger/           # Lambda relay + S3 event notification
│   └── gcp/                   # Cloud Function + Vertex AI
├── src/
│   ├── frontend/index.html    # Upload page (deployed to S3)
│   ├── lambda-relay/index.js  # Forwards S3 events to GCP
│   └── classify-function/     # Python Cloud Function
│       ├── main.py            # Classification + email logic
│       └── requirements.txt
└── README.md
```

## How It Works

1. User opens the static website hosted on **S3** (AWS)
2. Selects an image and clicks **Upload & Classify**
3. JavaScript PUTs the image to **API Gateway** → **S3** (AWS)
4. S3 event notification triggers the **Lambda relay** (AWS)
5. Lambda POSTs `{bucket, key}` to the **Cloud Function** (GCP)
6. Cloud Function downloads the image from S3, sends it to **Vertex AI Gemini** for classification
7. Classification results are emailed via **Azure Communication Services**

## Tear Down

Run the deploy workflow with `action = destroy` to remove all resources.

Destroy order (handled automatically):
1. AWS Trigger (Lambda + S3 notification)
2. GCP (Cloud Function)
3. AWS Core (S3 + API Gateway)
4. Azure (Communication Services)

**Note:** Bootstrap state backends must be destroyed separately if needed.

## Cost Estimate

All services used fall within free tiers for demo/testing:
- **AWS:** S3 free tier, Lambda 1M free requests/month, API Gateway 1M free calls/month
- **GCP:** Cloud Functions 2M free invocations/month, Vertex AI has pay-per-use pricing
- **Azure:** Communication Services free tier includes email

## Limitations

- API Gateway has a 10 MB payload limit (fine for most images)
- Azure Communication Services sends from `donotreply@<id>.azurecomm.net` — no custom domain
- GCP Cloud Function cold starts may add 3-5s on first invocation
- The Cloud Function URL is unauthenticated (for simplicity) — in production, add auth
