# Cloud Lens

Multi-cloud image classification pipeline across AWS, GCP, and Azure.

## Architecture

```
Browser → CloudFront → S3 (AWS)
  ↓
API Gateway → S3 Bucket [1-day retention]
  ↓
EventBridge → Cloud Function (GCP) [authenticated]
  ↓
Gemini (Gen AI SDK) → Azure Email → Inbox
```

| Cloud | Services |
|-------|----------|
| AWS | S3, API Gateway, EventBridge, CloudFront, IAM |
| GCP | Cloud Functions, Gemini (via Gen AI SDK), Secret Manager |
| Azure | Communication Services |

## Prerequisites

### Cloud Accounts

- AWS: IAM user with programmatic access
- GCP: Project with billing enabled + service account
- Azure: Subscription + service principal

### Enable GCP APIs

```bash
gcloud services enable \
  cloudfunctions.googleapis.com \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  aiplatform.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  storage.googleapis.com
```

## Setup

### 1. Create GitHub Environment

**Settings → Environments → New environment**

- Name: `cloud-lens`
- Click **Configure environment**

### 2. Add Environment Secrets

In the `cloud-lens` environment, add these secrets:

| Secret | How to Get |
|--------|------------|
| `AWS_ACCESS_KEY_ID` | AWS Console → IAM → Users → Security credentials |
| `AWS_SECRET_ACCESS_KEY` | Same as above |
| `GCP_SERVICE_ACCOUNT_KEY` | `base64 -i key.json` |
| `ARM_CLIENT_ID` | `az ad sp create-for-rbac` (see below) |
| `ARM_CLIENT_SECRET` | Same command output |
| `ARM_TENANT_ID` | `az account show --query tenantId -o tsv` |
| `ARM_SUBSCRIPTION_ID` | `az account show --query id -o tsv` |

**Quick Azure setup:**
```bash
az ad sp create-for-rbac \
  --name "cloud-lens-terraform" \
  --role Contributor \
  --scopes /subscriptions/$(az account show --query id -o tsv)
```

### 3. Add Environment Variables

In the `cloud-lens` environment, add these variables:

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `PROJECT_PREFIX` | `imgclass` | No | Resource name prefix |
| `NOTIFICATION_EMAIL` | — | Yes | Email for classification results |
| `GCP_PROJECT_ID` | — | Yes | Your GCP project ID |
| `AWS_REGION` | `us-east-1` | No | AWS region |
| `GCP_REGION` | `us-central1` | No | GCP region |
| `AZURE_LOCATION` | `eastus` | No | Azure region |

### 4. Bootstrap State Backends

**Actions → Setup Terraform State Backends → Run workflow**

Type `create` to confirm. Creates:
- AWS: S3 bucket (versioned, encrypted, native locking)
- GCP: GCS bucket (versioned)
- Azure: Storage account + container (versioned)

### 5. Deploy

**Actions → Deploy Multi-Cloud Image Classification → Run workflow**

Or push to `main` branch.

### 6. Access Application

Find CloudFront URL in GitHub Actions output or AWS Console.

## Configuration

### User-Modifiable Terraform Variables

These can be customized in `terraform/variables.tf` or via GitHub Variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `project_prefix` | `imgclass` | Prefix for all resources |
| `aws_region` | `us-east-1` | AWS deployment region |
| `gcp_region` | `us-central1` | GCP deployment region |
| `azure_location` | `eastus` | Azure deployment region |
| `notification_email` | — | Recipient email (required) |
| `gcp_project_id` | — | GCP project ID (required) |

GCP-specific (in `terraform/gcp/variables.tf`):

| Variable | Default | Description |
|----------|---------|-------------|
| `gemini_model` | `gemini-2.5-flash` | Gemini model via Gen AI SDK |

Note: Other variables are auto-populated from Terraform outputs during deployment.

## Local Development

**Prerequisites:** Terraform >= 1.5, AWS/gcloud/Azure CLIs configured, state backends created

**Setup:**
1. Uncomment backend config in `terraform/{aws,gcp,azure}/provider.tf`
2. Update with your account IDs
3. Deploy in order:

```bash
# 1. Azure
cd terraform/azure
terraform init
terraform apply -var="notification_email=you@example.com"

# 2. AWS (initial)
cd ../aws
terraform init
terraform apply \
  -var="gcp_function_url=https://placeholder" \
  -var="eventbridge_auth_token=placeholder" \
  -var="gcp_service_account_unique_id=placeholder"

# 3. GCP
cd ../gcp
terraform init
terraform apply \
  -var="gcp_project_id=your-project-id" \
  -var="s3_bucket_name=$(cd ../aws && terraform output -raw image_bucket_name)" \
  -var="aws_role_arn=$(cd ../aws && terraform output -raw gcp_function_role_arn)" \
  -var="azure_email_connection_string=$(cd ../azure && terraform output -raw communication_service_connection_string)" \
  -var="azure_sender_address=$(cd ../azure && terraform output -raw sender_address)" \
  -var="notification_email=you@example.com"

# 4. Update AWS
cd ../aws
terraform apply \
  -var="gcp_function_url=$(cd ../gcp && terraform output -raw function_url)" \
  -var="eventbridge_auth_token=$(cd ../gcp && terraform output -raw eventbridge_auth_token)" \
  -var="gcp_service_account_unique_id=$(cd ../gcp && terraform output -raw service_account_unique_id)"
```

## Cleanup

**Destroy Infrastructure:** Actions → Destroy Multi-Cloud Infrastructure (type `DESTROY`)

**Destroy State Backends:** Actions → Cleanup Terraform State Backends (type `DELETE`)

## How It Works

1. User uploads image via CloudFront website
2. API Gateway stores image in S3
3. S3 event triggers EventBridge
4. EventBridge invokes GCP Cloud Function (authenticated)
5. Function uses Workload Identity Federation for AWS access
6. Downloads image, classifies with Gemini (Google Gen AI SDK)
7. Sends styled email via Azure Communication Services
8. Image auto-deletes after 1 day

## Security

- HTTPS via CloudFront
- Workload Identity Federation (no stored AWS keys)
- Secrets in GCP Secret Manager
- Auto-delete images (1 day)
- Authenticated EventBridge → GCP
- Input validation + HTML escaping

## Cost

Free tier eligible:
- AWS: S3, API Gateway (1M/month), EventBridge (14M/month)
- GCP: Cloud Functions (2M/month), Gemini API (pay-per-use)
- Azure: Communication Services (free tier)

## Troubleshooting

**GCP APIs:** `gcloud services enable <service>.googleapis.com`

**State Lock (GCP):** Delete lock file from GCS bucket manually

**GitHub Actions:** Verify secrets/variables, check quotas, review logs
