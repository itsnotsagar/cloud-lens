# =============================================================================
# S3 Bucket for Image Uploads (private)
# =============================================================================

resource "aws_s3_bucket" "images" {
  bucket = "${var.project_prefix}-images-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# S3 Lifecycle Policy - Auto-delete images after 1 day
# =============================================================================

resource "aws_s3_bucket_lifecycle_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    id     = "delete-old-images"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 1
    }
  }
}

# =============================================================================
# S3 Static Website Bucket
# =============================================================================

resource "aws_s3_bucket" "website" {
  bucket = "${var.project_prefix}-website-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  depends_on = [aws_s3_bucket_public_access_block.website]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.website.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website.arn
          }
        }
      }
    ]
  })
}

# =============================================================================
# CloudFront Distribution — HTTPS for the static website
# =============================================================================

resource "aws_cloudfront_origin_access_control" "website" {
  name                              = "${var.project_prefix}-website-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "website" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "${var.project_prefix} website"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "s3-website"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-website"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Upload the frontend HTML — uses templatefile to inject API Gateway URL
resource "aws_s3_object" "index_html" {
  bucket = aws_s3_bucket.website.id
  key    = "index.html"
  content = templatefile("${path.module}/../../src/frontend/index.html", {
    api_gateway_url     = aws_api_gateway_stage.prod.invoke_url
    api_gateway_api_key = aws_api_gateway_api_key.frontend.value
  })
  content_type  = "text/html"
  cache_control = "no-cache"
  etag = md5(templatefile("${path.module}/../../src/frontend/index.html", {
    api_gateway_url     = aws_api_gateway_stage.prod.invoke_url
    api_gateway_api_key = aws_api_gateway_api_key.frontend.value
  }))
}

# Upload the CSS file
resource "aws_s3_object" "styles_css" {
  bucket       = aws_s3_bucket.website.id
  key          = "styles.css"
  source       = "${path.module}/../../src/frontend/styles.css"
  content_type = "text/css"
  etag         = filemd5("${path.module}/../../src/frontend/styles.css")
}

# Enable EventBridge notifications on S3 bucket
resource "aws_s3_bucket_notification" "eventbridge" {
  bucket      = aws_s3_bucket.images.id
  eventbridge = true
}
