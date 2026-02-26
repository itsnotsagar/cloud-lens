# =============================================================================
# IAM Role for API Gateway to write to S3
# =============================================================================

resource "aws_iam_role" "api_gateway_s3" {
  name = "${var.project_prefix}-apigw-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = var.project_prefix
  }
}

resource "aws_iam_role_policy" "api_gateway_s3" {
  name = "${var.project_prefix}-apigw-s3-policy"
  role = aws_iam_role.api_gateway_s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.images.arn}/*"
      }
    ]
  })
}
