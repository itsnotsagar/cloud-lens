# Terraform Structure

This directory contains Terraform configurations organized by cloud provider following best practices.

## Directory Structure

```
terraform/
├── aws/                    # AWS resources (S3, API Gateway, EventBridge, Lambda)
│   ├── provider.tf        # AWS provider configuration
│   ├── variables.tf       # Input variables
│   ├── outputs.tf         # Output values
│   ├── data.tf            # Data sources
│   ├── iam.tf             # IAM roles and policies
│   ├── s3.tf              # S3 buckets and configuration
│   ├── api-gateway.tf     # API Gateway configuration
│   ├── lambda.tf          # Lambda functions
│   └── eventbridge.tf     # EventBridge rules and targets
│
├── gcp/                    # GCP resources (Cloud Functions, Secret Manager)
│   ├── provider.tf        # GCP provider configuration
│   ├── variables.tf       # Input variables
│   ├── outputs.tf         # Output values
│   ├── iam.tf             # Service accounts and IAM bindings
│   ├── cloud-function.tf  # Cloud Function configuration
│   └── secrets.tf         # Secret Manager secrets
│
├── azure/                  # Azure resources (Communication Services)
│   ├── provider.tf        # Azure provider configuration
│   ├── variables.tf       # Input variables
│   ├── outputs.tf         # Output values
│   └── communication-services.tf  # Email service configuration
│
├── variables.tf            # Root-level variables (optional)
└── terraform.tfvars.example  # Example variable values
```

## Deployment Order

Due to cross-cloud dependencies, modules must be deployed in this order:

### 1. Azure (no dependencies)
```bash
cd terraform/azure
terraform init
terraform plan
terraform apply
```

### 2. AWS (no dependencies, but creates resources needed by GCP)
```bash
cd terraform/aws
terraform init
terraform plan -var="gcp_function_url=https://placeholder" -var="eventbridge_auth_token=placeholder"
terraform apply -var="gcp_function_url=https://placeholder" -var="eventbridge_auth_token=placeholder"
```

### 3. GCP (depends on Azure and AWS outputs)
```bash
cd terraform/gcp
terraform init
terraform plan \
  -var="s3_bucket_name=$(cd ../aws && terraform output -raw image_bucket_name)" \
  -var="aws_access_key_id=$(cd ../aws && terraform output -raw gcp_function_aws_access_key_id)" \
  -var="aws_secret_access_key=$(cd ../aws && terraform output -raw gcp_function_aws_secret_access_key)" \
  -var="azure_email_connection_string=$(cd ../azure && terraform output -raw communication_service_connection_string)" \
  -var="azure_sender_address=$(cd ../azure && terraform output -raw sender_address)"
terraform apply
```

### 4. AWS (update with GCP function URL)
```bash
cd terraform/aws
terraform plan \
  -var="gcp_function_url=$(cd ../gcp && terraform output -raw function_url)" \
  -var="eventbridge_auth_token=$(cd ../gcp && terraform output -raw eventbridge_auth_token)"
terraform apply
```

## Best Practices Implemented

### 1. **Separation of Concerns**
- Each cloud provider has its own directory
- Resources are split into logical files (iam.tf, s3.tf, etc.)
- Clear naming conventions

### 2. **Provider Configuration**
- Each module has its own `provider.tf`
- Default tags/labels applied at provider level
- Backend configuration in provider file

### 3. **Resource Organization**
- IAM resources in `iam.tf`
- Storage resources in dedicated files
- Compute resources in dedicated files
- Networking/API resources in dedicated files

### 4. **Variables and Outputs**
- All variables defined in `variables.tf`
- All outputs defined in `outputs.tf`
- Sensitive values marked appropriately
- Clear descriptions for all variables/outputs

### 5. **Data Sources**
- Centralized in `data.tf` (AWS)
- Keeps resource files clean

### 6. **State Management**
- Remote state backends configured
- State isolation per cloud provider
- Encryption enabled

## Module Dependencies

```
Azure (Communication Services)
  ↓
  ├─→ GCP (needs email connection string)
  │
AWS (S3, IAM User)
  ↓
  ├─→ GCP (needs S3 bucket name and AWS credentials)
  │
GCP (Cloud Function, Secrets)
  ↓
  └─→ AWS (needs function URL and auth token for EventBridge)
```

## Variables

### Common Variables (all modules)
- `project_prefix` - Prefix for resource names (default: "imgclass")
- `environment` - Environment name (default: "production")

### AWS-specific
- `aws_region` - AWS region (default: "us-east-1")
- `gcp_function_url` - GCP function URL (from GCP module)
- `eventbridge_auth_token` - Auth token (from GCP module)

### GCP-specific
- `gcp_project_id` - GCP project ID (required)
- `gcp_region` - GCP region (default: "us-central1")
- `s3_bucket_name` - S3 bucket name (from AWS module)
- `aws_access_key_id` - AWS access key (from AWS module)
- `aws_secret_access_key` - AWS secret key (from AWS module)
- `azure_email_connection_string` - Azure connection string (from Azure module)
- `azure_sender_address` - Azure sender email (from Azure module)
- `notification_email` - Recipient email (required)

### Azure-specific
- `azure_location` - Azure region (default: "eastus")
- `notification_email` - Recipient email (required)

## Outputs

### AWS Outputs
- `image_bucket_name` - S3 bucket for images
- `website_url` - Static website URL
- `api_gateway_invoke_url` - API Gateway URL
- `gcp_function_aws_access_key_id` - AWS credentials for GCP (sensitive)
- `gcp_function_aws_secret_access_key` - AWS credentials for GCP (sensitive)

### GCP Outputs
- `function_url` - Cloud Function URL
- `eventbridge_auth_token` - Auth token for EventBridge (sensitive)
- Secret Manager secret IDs

### Azure Outputs
- `sender_address` - Email sender address
- `communication_service_connection_string` - Connection string (sensitive)

## GitHub Actions Integration

The GitHub Actions workflows handle the deployment order automatically:

1. `deploy-azure` - Deploys Azure module
2. `deploy-aws` - Deploys AWS module (with placeholder values)
3. `deploy-gcp` - Deploys GCP module (with Azure and AWS outputs)
4. `update-aws` - Updates AWS module (with GCP outputs)

See `.github/workflows/deploy.yml` for implementation details.

## Local Development

For local development, you can use terraform workspaces or separate tfvars files:

```bash
# Development environment
terraform workspace new dev
terraform apply -var-file="dev.tfvars"

# Production environment
terraform workspace new prod
terraform apply -var-file="prod.tfvars"
```

## Cleanup

To destroy resources, reverse the deployment order:

```bash
cd terraform/aws && terraform destroy
cd terraform/gcp && terraform destroy
cd terraform/azure && terraform destroy
```

Or use the GitHub Actions destroy workflow.
