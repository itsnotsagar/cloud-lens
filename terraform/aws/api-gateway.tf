# =============================================================================
# API Gateway — proxies PUT requests to S3
# =============================================================================

locals {
  cors_origin = "'http://${aws_s3_bucket_website_configuration.website.website_endpoint}'"
}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project_prefix}-api"
  description = "API Gateway to proxy image uploads to S3"

  binary_media_types = ["image/*"]

  endpoint_configuration {
    types = ["REGIONAL"]
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
  rest_api_id      = aws_api_gateway_rest_api.main.id
  resource_id      = aws_api_gateway_resource.upload_filename.id
  http_method      = "PUT"
  authorization    = "NONE"
  api_key_required = true

  request_parameters = {
    "method.request.path.filename"       = true
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
    "integration.request.path.filename"       = "method.request.path.filename"
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
    "method.response.header.Access-Control-Allow-Origin" = local.cors_origin
  }

  depends_on = [aws_api_gateway_integration.put_s3]
}

# =============================================================================
# CORS: Mock-backed OPTIONS (no Lambda needed)
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
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.upload_filename.id
  http_method = aws_api_gateway_method.options_upload.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Headers" = true
  }
}

resource "aws_api_gateway_integration_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.upload_filename.id
  http_method = aws_api_gateway_method.options_upload.http_method
  status_code = aws_api_gateway_method_response.options_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = local.cors_origin
    "method.response.header.Access-Control-Allow-Methods" = "'PUT,OPTIONS'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,Accept,X-Amz-Date,Authorization,X-Api-Key'"
  }

  depends_on = [aws_api_gateway_integration.options_upload]
}

# =============================================================================
# Gateway Responses — ensure CORS headers on ALL responses
# =============================================================================

resource "aws_api_gateway_gateway_response" "default_4xx" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  response_type = "DEFAULT_4XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = local.cors_origin
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,Accept,X-Amz-Date,Authorization,X-Api-Key'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'PUT,OPTIONS'"
  }
}

resource "aws_api_gateway_gateway_response" "default_5xx" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  response_type = "DEFAULT_5XX"

  response_parameters = {
    "gatewayresponse.header.Access-Control-Allow-Origin"  = local.cors_origin
    "gatewayresponse.header.Access-Control-Allow-Headers" = "'Content-Type,Accept,X-Amz-Date,Authorization,X-Api-Key'"
    "gatewayresponse.header.Access-Control-Allow-Methods" = "'PUT,OPTIONS'"
  }
}

# =============================================================================
# API Gateway Deployment
# =============================================================================

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.put_upload.id,
      aws_api_gateway_integration.put_s3.id,
      aws_api_gateway_method_response.put_200.id,
      aws_api_gateway_integration_response.put_200.id,
      aws_api_gateway_integration_response.put_200.response_parameters,
      aws_api_gateway_method.options_upload.id,
      aws_api_gateway_integration.options_upload.id,
      aws_api_gateway_method_response.options_200.id,
      aws_api_gateway_integration_response.options_200.response_parameters,
      aws_api_gateway_gateway_response.default_4xx.response_parameters,
      aws_api_gateway_gateway_response.default_5xx.response_parameters,
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
    aws_api_gateway_gateway_response.default_4xx,
    aws_api_gateway_gateway_response.default_5xx,
  ]
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = "prod"

  depends_on = [aws_api_gateway_account.main]

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      resourcePath   = "$context.resourcePath"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      errorMessage   = "$context.error.message"
    })
  }
}

# =============================================================================
# API Gateway Access Logs
# =============================================================================

resource "aws_cloudwatch_log_group" "api_gateway_access" {
  name              = "/aws/apigateway/${var.project_prefix}-api/access-logs"
  retention_in_days = 30
}

# =============================================================================
# API Key + Usage Plan for rate limiting and auth
# =============================================================================

resource "aws_api_gateway_api_key" "frontend" {
  name    = "${var.project_prefix}-frontend-key"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "default" {
  name = "${var.project_prefix}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.main.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    burst_limit = 10
    rate_limit  = 5
  }

  quota_settings {
    limit  = 500
    period = "DAY"
  }
}

resource "aws_api_gateway_usage_plan_key" "frontend" {
  key_id        = aws_api_gateway_api_key.frontend.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.default.id
}
