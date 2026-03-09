# =============================================================================
# EventBridge Rule - Trigger on S3 Object Created events
# =============================================================================

resource "aws_cloudwatch_event_rule" "s3_upload" {
  name        = "${var.project_prefix}-s3-upload-rule"
  description = "Trigger when images are uploaded to S3"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [aws_s3_bucket.images.id]
      }
    }
  })
}

# =============================================================================
# EventBridge Connection - Stores authentication credentials
# =============================================================================

resource "aws_cloudwatch_event_connection" "gcp_function" {
  name        = "${var.project_prefix}-gcp-function-connection"
  description = "Connection to GCP Cloud Function with authentication"

  authorization_type = "API_KEY"

  auth_parameters {
    api_key {
      key   = "X-Auth-Token"
      value = var.eventbridge_auth_token
    }
  }
}

# =============================================================================
# EventBridge API Destination - Target GCP Function URL
# =============================================================================

resource "aws_cloudwatch_event_api_destination" "gcp_function" {
  name                             = "${var.project_prefix}-gcp-function-destination"
  description                      = "API Destination for GCP Cloud Function"
  invocation_endpoint              = var.gcp_function_url
  http_method                      = "POST"
  invocation_rate_limit_per_second = 10
  connection_arn                   = aws_cloudwatch_event_connection.gcp_function.arn
}

# =============================================================================
# EventBridge Target - Send S3 events to API Destination
# =============================================================================

resource "aws_cloudwatch_event_target" "gcp_function" {
  rule      = aws_cloudwatch_event_rule.s3_upload.name
  target_id = "${var.project_prefix}-gcp-function-target"
  arn       = aws_cloudwatch_event_api_destination.gcp_function.arn
  role_arn  = aws_iam_role.eventbridge_invoke_api_destination.arn

  # Transform S3 event to match GCP function expected format
  input_transformer {
    input_paths = {
      bucket    = "$.detail.bucket.name"
      key       = "$.detail.object.key"
      size      = "$.detail.object.size"
      timestamp = "$.time"
    }

    input_template = <<-JSON
    {
      "bucket": "<bucket>",
      "key": "<key>",
      "size": <size>,
      "timestamp": "<timestamp>",
      "event": "s3:ObjectCreated"
    }
    JSON
  }

  retry_policy {
    maximum_retry_attempts       = 2
    maximum_event_age_in_seconds = 180
  }
}

# =============================================================================
# CloudWatch Log Group for EventBridge (optional but recommended)
# =============================================================================

resource "aws_cloudwatch_log_group" "eventbridge" {
  name              = "/aws/events/${var.project_prefix}-s3-upload-rule"
  retention_in_days = 30
}
