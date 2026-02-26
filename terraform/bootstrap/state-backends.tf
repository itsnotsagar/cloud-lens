# =============================================================================
# AWS State Backend: S3 with native locking
# =============================================================================

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_prefix}-tf-state-aws"

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "${var.project_prefix}-tf-state"
    Project = var.project_prefix
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# GCP State Backend: GCS bucket
# =============================================================================

resource "google_storage_bucket" "terraform_state" {
  name          = "${var.project_prefix}-tf-state-gcp"
  location      = var.gcp_region
  force_destroy = false

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true

  labels = {
    project = var.project_prefix
  }
}

# =============================================================================
# Azure State Backend: Resource Group + Storage Account + Container
# =============================================================================

resource "azurerm_resource_group" "terraform_state" {
  name     = "${var.project_prefix}-tf-state-rg"
  location = var.azure_location

  tags = {
    Project = var.project_prefix
  }
}

resource "azurerm_storage_account" "terraform_state" {
  name                     = "${replace(var.project_prefix, "-", "")}tfstate"
  resource_group_name      = azurerm_resource_group.terraform_state.name
  location                 = azurerm_resource_group.terraform_state.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    Project = var.project_prefix
  }
}

resource "azurerm_storage_container" "terraform_state" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.terraform_state.name
  container_access_type = "private"
}
