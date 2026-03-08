output "image_bucket_name" {
  description = "Name of the S3 bucket for image uploads"
  value       = aws_s3_bucket.images.id
}

output "image_bucket_arn" {
  description = "ARN of the S3 bucket for image uploads"
  value       = aws_s3_bucket.images.arn
}

output "website_url" {
  description = "URL of the static website (CloudFront HTTPS)"
  value       = "https://${aws_cloudfront_distribution.website.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for cache invalidation"
  value       = aws_cloudfront_distribution.website.id
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

output "gcp_function_role_arn" {
  description = "ARN of the IAM role for GCP function to assume via Workload Identity Federation"
  value       = aws_iam_role.gcp_function_s3_reader.arn
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
