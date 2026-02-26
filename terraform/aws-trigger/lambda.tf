# =============================================================================
# Lambda Relay Function — forwards S3 events to GCP Cloud Function
# =============================================================================

# Package the Lambda code
data "archive_file" "lambda_relay" {
  type        = "zip"
  source_dir  = "${path.module}/../../src/lambda-relay"
  output_path = "${path.module}/../../.build/lambda-relay.zip"
}

resource "aws_lambda_function" "relay" {
  function_name    = "${var.project_prefix}-relay"
  role             = aws_iam_role.lambda_relay.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.lambda_relay.output_path
  source_code_hash = data.archive_file.lambda_relay.output_base64sha256

  environment {
    variables = {
      GCP_FUNCTION_URL = var.gcp_function_url
    }
  }

  tags = {
    Project = var.project_prefix
  }
}

# =============================================================================
# IAM Role for Lambda
# =============================================================================

resource "aws_iam_role" "lambda_relay" {
  name = "${var.project_prefix}-lambda-relay-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Project = var.project_prefix
  }
}

resource "aws_iam_role_policy" "lambda_relay" {
  name = "${var.project_prefix}-lambda-relay-policy"
  role = aws_iam_role.lambda_relay.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${var.image_bucket_arn}/*"
      }
    ]
  })
}

# =============================================================================
# S3 Event Notification → Lambda
# =============================================================================

resource "aws_lambda_permission" "s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.relay.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.image_bucket_arn
}

resource "aws_s3_bucket_notification" "image_upload" {
  bucket = var.image_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.relay.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3]
}
