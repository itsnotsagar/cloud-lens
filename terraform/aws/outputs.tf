output "image_bucket_name" {
  description = "Name of the S3 bucket for image uploads"
  value       = aws_s3_bucket.images.id
}

output "image_bucket_arn" {
  description = "ARN of the S3 bucket for image uploads"
  value       = aws_s3_bucket.images.arn
}

output "website_url" {
  description = "URL of the static website"
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
}

output "api_gateway_invoke_url" {
  description = "API Gateway invocation URL"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "api_gateway_api_key" {
  description = "API key for the frontend to authenticate with API Gateway"
  value       = aws_api_gateway_api_key.frontend.value
  sensitive   = true
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "gcp_function_aws_access_key_id" {
  description = "AWS access key ID for GCP function (restricted to S3 read-only)"
  value       = aws_iam_access_key.gcp_function_s3_reader.id
  sensitive   = true
}

output "gcp_function_aws_secret_access_key" {
  description = "AWS secret access key for GCP function (restricted to S3 read-only)"
  value       = aws_iam_access_key.gcp_function_s3_reader.secret
  sensitive   = true
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.s3_upload.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.s3_upload.arn
}

output "api_destination_arn" {
  description = "ARN of the EventBridge API Destination"
  value       = aws_cloudwatch_event_api_destination.gcp_function.arn
}
