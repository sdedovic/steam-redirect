locals {
  name = "steam-redirect"

  log_retention_days = 30

  domain_name = join(".", compact([var.subdomain, var.hosted_zone_id]))
}

### Logging ### 

# destination of API gateway logs
resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/api-gw/${local.name}"
  retention_in_days = local.log_retention_days
}

# destination of lambda logs
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = local.log_retention_days
}


### DNS ###

data "aws_route53_zone" "default" {
  name         = var.hosted_zone_id
  private_zone = false
}

# TLS cert
resource "aws_acm_certificate" "default" {
  domain_name       = local.domain_name
  validation_method = "DNS"
}

# DNS validation for TLS cert
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.default.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.default.zone_id
}

# terraform resource to wait for DNS-based validation
resource "aws_acm_certificate_validation" "default" {
  certificate_arn         = aws_acm_certificate.default.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}


### API Gateway (HTTP) ###

# custom domain for API gateway
resource "aws_apigatewayv2_domain_name" "default" {
  domain_name = local.domain_name

  domain_name_configuration {
    certificate_arn = aws_acm_certificate.default.arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api" "default" {
  name        = local.name
  description = "API that triggers Lambda function execution"

  disable_execute_api_endpoint = true
  protocol_type                = "HTTP"

  # disable everything
  cors_configuration {
    allow_credentials = false
    allow_headers     = []
    allow_methods     = []
    allow_origins     = []
    expose_headers    = []
    max_age           = 0
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.default.id
  name        = "default"
  description = "Default and only deployment stage"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn

    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      protocol       = "$context.protocol"
      responseLength = "$context.responseLength"
    })
  }
}

resource "aws_apigatewayv2_api_mapping" "default" {
  api_id      = aws_apigatewayv2_api.default.id
  domain_name = aws_apigatewayv2_domain_name.default.id
  stage       = aws_apigatewayv2_stage.default.id
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id      = aws_apigatewayv2_api.default.id
  description = "Lambda invocation integration"

  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.redirect.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.default.id
  route_key = "$default"

  target = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.redirect.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.default.execution_arn}/*/*"
}


### Lambda Function ###

# code executed by lambda function
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "src/index.mjs"
  output_path = "lambda-function.zip"
}

# the lambda function
resource "aws_lambda_function" "redirect" {
  function_name = local.name

  runtime       = "nodejs20.x"
  architectures = ["x86_64"]

  # minimums
  memory_size = 128
  ephemeral_storage {
    size = 512
  }

  handler          = "index.handler"
  package_type     = "Zip"
  filename         = "lambda-function.zip"
  source_code_hash = data.archive_file.lambda.output_base64sha256
  publish          = false

  role = aws_iam_role.lambda.arn

  logging_config {
    log_format = "Text"
    log_group  = "/aws/lambda/${local.name}"
  }

  tracing_config {
    mode = "PassThrough"
  }
}

# allow writing logs
resource "aws_iam_policy" "basic_execution" {
  path = "/service-role/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
      }
    ]
  })
}

# define role for lambda
resource "aws_iam_role" "lambda" {
  name_prefix = local.name
  path        = "/service-role/"
  description = "Role assumed by Lambda function during execution for accessing AWS resources."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
  managed_policy_arns = [aws_iam_policy.basic_execution.arn]
}
