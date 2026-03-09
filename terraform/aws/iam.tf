# =============================================================================
# IAM Role for API Gateway CloudWatch Logging (account-level)
# =============================================================================

resource "aws_iam_role" "api_gateway_cloudwatch" {
  name = "${var.project_prefix}-apigw-cloudwatch-role"

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
}

resource "aws_iam_role_policy_attachment" "api_gateway_cloudwatch" {
  role       = aws_iam_role.api_gateway_cloudwatch.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_api_gateway_account" "main" {
  cloudwatch_role_arn = aws_iam_role.api_gateway_cloudwatch.arn
}

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

# =============================================================================
# OIDC Provider for GCP Workload Identity Federation
# =============================================================================

resource "aws_iam_openid_connect_provider" "gcp" {
  url             = "https://accounts.google.com"
  client_id_list  = [var.gcp_service_account_unique_id]
  thumbprint_list = ["08745487e891c19e3078c1f2a07e452950ef36f6"]
}

# =============================================================================
# IAM Role for GCP Function (S3 Read-Only via Workload Identity Federation)
# =============================================================================

resource "aws_iam_role" "gcp_function_s3_reader" {
  name = "${var.project_prefix}-gcp-function-s3-reader-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRoleWithWebIdentity"
        Principal = {
          Federated = aws_iam_openid_connect_provider.gcp.arn
        }
        Condition = {
          StringEquals = {
            "accounts.google.com:sub" = var.gcp_service_account_unique_id
            "accounts.google.com:aud" = var.gcp_service_account_unique_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "gcp_function_s3_reader" {
  name = "${var.project_prefix}-gcp-s3-read-only"
  role = aws_iam_role.gcp_function_s3_reader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.images.arn}/*"
      }
    ]
  })
}

# =============================================================================
# IAM Role for EventBridge to invoke API Destination
# =============================================================================

resource "aws_iam_role" "eventbridge_invoke_api_destination" {
  name = "${var.project_prefix}-eventbridge-api-destination-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_invoke_api_destination" {
  name = "${var.project_prefix}-eventbridge-invoke-policy"
  role = aws_iam_role.eventbridge_invoke_api_destination.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "events:InvokeApiDestination"
        ]
        Resource = aws_cloudwatch_event_api_destination.gcp_function.arn
      }
    ]
  })
}
