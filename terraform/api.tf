# POST /messages, IAM-signed (SigV4). Callers need execute-api:Invoke on this route.

resource "aws_apigatewayv2_api" "guard" {
  name          = local.name
  protocol_type = "HTTP"
  description   = "Support-message guard: System One decision circuit"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type", "x-amz-date", "authorization", "x-amz-security-token"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_integration" "guard" {
  api_id                 = aws_apigatewayv2_api.guard.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.guard.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000
}

resource "aws_apigatewayv2_route" "messages" {
  api_id             = aws_apigatewayv2_api.guard.id
  route_key          = "POST /messages"
  authorization_type = "AWS_IAM"
  target             = "integrations/${aws_apigatewayv2_integration.guard.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.guard.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_rate_limit  = var.throttle_rate
    throttling_burst_limit = var.throttle_burst
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId = "$context.requestId"
      caller    = "$context.identity.caller"
      route     = "$context.routeKey"
      status    = "$context.status"
      latencyMs = "$context.responseLatency"
      error     = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guard.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.guard.execution_arn}/*/POST/messages"
}
