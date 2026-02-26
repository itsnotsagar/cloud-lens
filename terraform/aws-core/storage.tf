# =============================================================================
# S3 Bucket for Image Uploads (private)
# =============================================================================

resource "aws_s3_bucket" "images" {
  bucket = "${var.project_prefix}-images-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "${var.project_prefix}-images"
    Project = var.project_prefix
  }
}

resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["*"] # In production, restrict to your domain
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}

# =============================================================================
# S3 Static Website Bucket
# =============================================================================

resource "aws_s3_bucket" "website" {
  bucket = "${var.project_prefix}-website-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "${var.project_prefix}-website"
    Project = var.project_prefix
  }
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  depends_on = [aws_s3_bucket_public_access_block.website]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })
}

# Upload the frontend HTML — uses templatefile to inject API Gateway URL
resource "aws_s3_object" "index_html" {
  bucket = aws_s3_bucket.website.id
  key    = "index.html"
  content = templatefile("${path.module}/../../src/frontend/index.html", {
    api_gateway_url = aws_api_gateway_deployment.main.invoke_url
  })
  content_type = "text/html"
  etag = md5(templatefile("${path.module}/../../src/frontend/index.html", {
    api_gateway_url = aws_api_gateway_deployment.main.invoke_url
  }))
}
