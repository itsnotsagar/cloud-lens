output "image_bucket_name" {
  value = aws_s3_bucket.images.id
}

output "image_bucket_arn" {
  value = aws_s3_bucket.images.arn
}

output "website_url" {
  value = aws_s3_bucket_website_configuration.website.website_endpoint
}

output "api_gateway_invoke_url" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "aws_region" {
  value = var.aws_region
}

output "aws_account_id" {
  value = data.aws_caller_identity.current.account_id
}
