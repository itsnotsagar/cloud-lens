# =============================================================================
# CORS Lambda Function
# =============================================================================

data "archive_file" "cors_lambda" {
  type                    = "zip"
  source_content          = <<-PYTHON
import os

ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "*")

def handler(event, context):
    return {
        "statusCode": 200,
        "headers": {
            "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
            "Access-Control-Allow-Methods": "PUT,OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type,Accept,X-Amz-Date,Authorization,X-Api-Key",
        },
        "body": "",
    }
PYTHON
  source_content_filename = "cors.py"
  output_path             = "${path.root}/.build/cors_lambda.zip"
}

resource "aws_lambda_function" "cors" {
  function_name    = "${var.project_prefix}-cors"
  role             = aws_iam_role.cors_lambda.arn
  handler          = "cors.handler"
  runtime          = "python3.11"
  filename         = data.archive_file.cors_lambda.output_path
  source_code_hash = data.archive_file.cors_lambda.output_base64sha256

  environment {
    variables = {
      ALLOWED_ORIGIN = "http://${aws_s3_bucket_website_configuration.website.website_endpoint}"
    }
  }
}

resource "aws_lambda_permission" "cors_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cors.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# CloudWatch Logs retention for CORS Lambda
# Note: Lambda automatically creates this log group, we just set retention
resource "aws_cloudwatch_log_group" "cors_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.cors.function_name}"
  retention_in_days = 30

  lifecycle {
    prevent_destroy       = false
    ignore_changes        = [name]
    create_before_destroy = false
  }

  depends_on = [aws_lambda_function.cors]
}
