# =============================================================================
# API Gateway — proxies PUT requests to S3
# =============================================================================

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_prefix}-api"
  description = "API Gateway to proxy image uploads to S3"

  binary_media_types = ["image/jpeg", "image/png", "image/webp"]

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Project = var.project_prefix
  }
}

# /upload resource
resource "aws_api_gateway_resource" "upload" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "upload"
}

# /upload/{filename} resource
resource "aws_api_gateway_resource" "upload_filename" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.upload.id
  path_part   = "{filename}"
}

# PUT method on /upload/{filename}
resource "aws_api_gateway_method" "put_upload" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.upload_filename.id
  http_method   = "PUT"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.filename"    = true
    "method.request.header.Content-Type" = false
  }
}

# Integration: PUT to S3
resource "aws_api_gateway_integration" "put_s3" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.upload_filename.id
  http_method             = aws_api_gateway_method.put_upload.http_method
  integration_http_method = "PUT"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:${var.aws_region}:s3:path/${aws_s3_bucket.images.id}/{filename}"
  credentials             = aws_iam_role.api_gateway_s3.arn

  request_parameters = {
    "integration.request.path.filename"    = "method.request.path.filename"
    "integration.request.header.Content-Type" = "method.request.header.Content-Type"
  }
}

# Method response for PUT
resource "aws_api_gateway_method_response" "put_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.upload_filename.id
  http_method = aws_api_gateway_method.put_upload.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

# Integration response for PUT
resource "aws_api_gateway_integration_response" "put_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.upload_filename.id
  http_method = aws_api_gateway_method.put_upload.http_method
  status_code = aws_api_gateway_method_response.put_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  depends_on = [aws_api_gateway_integration.put_s3]
}

# =============================================================================
# CORS: OPTIONS method for preflight
# =============================================================================

resource "aws_api_gateway_method" "options_upload" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.upload_filename.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_upload" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.upload_filename.id
  http_method = aws_api_gateway_method.options_upload.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({ statusCode = 200 })
  }

  passthrough_behavior = "WHEN_NO_MATCH"
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.upload_filename.id
  http_method = aws_api_gateway_method.options_upload.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.upload_filename.id
  http_method = aws_api_gateway_method.options_upload.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Accept,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'PUT,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }

  response_templates = {
    "application/json" = ""
  }

  depends_on = [aws_api_gateway_integration.options_upload]
}

# =============================================================================
# API Gateway Deployment
# =============================================================================

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.put_upload,
      aws_api_gateway_integration.put_s3,
      aws_api_gateway_method_response.put_200,
      aws_api_gateway_integration_response.put_200,
      aws_api_gateway_method.options_upload,
      aws_api_gateway_integration.options_upload,
      aws_api_gateway_method_response.options_200,
      aws_api_gateway_integration_response.options_200,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.put_s3,
    aws_api_gateway_integration_response.put_200,
    aws_api_gateway_integration.options_upload,
    aws_api_gateway_integration_response.options_200,
  ]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"

  tags = {
    Project = var.project_prefix
  }
}
