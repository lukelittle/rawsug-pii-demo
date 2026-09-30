# Checks against mocked providers: no AWS account, no credentials, nothing created.
# Run: terraform -chdir=terraform test

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  # Mocked ARNs must still parse as ARNs.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock" }
  }
  mock_resource "aws_lambda_layer_version" {
    defaults = { arn = "arn:aws:lambda:us-east-1:123456789012:layer:mock:1" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/mock" }
  }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:us-east-1:123456789012:mock" }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:mock" }
  }
  mock_resource "aws_lambda_function" {
    defaults = {
      arn        = "arn:aws:lambda:us-east-1:123456789012:function:mock"
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:mock/invocations"
    }
  }
  mock_resource "aws_apigatewayv2_api" {
    defaults = { execution_arn = "arn:aws:execute-api:us-east-1:123456789012:mock" }
  }
}

mock_provider "archive" {}

run "api_requires_sigv4" {
  command = apply # mocked: nothing reaches AWS

  assert {
    condition     = aws_apigatewayv2_route.messages.authorization_type == "AWS_IAM"
    error_message = "POST /messages must require IAM auth"
  }
}

run "only_xray_gets_a_wildcard" {
  command = apply # mocked: nothing reaches AWS

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.guard.statement :
      s.sid == "XRay" || !contains(s.resources, "*")
    ])
    error_message = "Only the X-Ray statement may use Resource \"*\""
  }
}

run "bedrock_scoped_to_one_profile" {
  command = apply # mocked: nothing reaches AWS

  assert {
    condition     = local.bedrock_profile_arn == "arn:aws:bedrock:us-east-1:123456789012:inference-profile/us.amazon.nova-2-lite-v1:0"
    error_message = "Bedrock profile ARN is wrong"
  }
  assert {
    condition     = local.bedrock_foundation_arn == "arn:aws:bedrock:*::foundation-model/amazon.nova-2-lite-v1:0"
    error_message = "Foundation model ARN is wrong"
  }
  assert {
    condition = anytrue([
      for s in data.aws_iam_policy_document.guard.statement :
      s.sid == "BedrockModel" && length(s.condition) == 1
    ])
    error_message = "Through a profile, the base model must be conditioned on that profile"
  }
}

run "bedrock_base_model_stays_in_region" {
  command = apply # mocked: nothing reaches AWS

  variables {
    bedrock_model_id = "amazon.nova-lite-v1:0"
  }

  assert {
    condition     = local.bedrock_foundation_arn == "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-lite-v1:0"
    error_message = "A base model ID must be scoped to this region"
  }
  assert {
    condition     = !contains([for s in data.aws_iam_policy_document.guard.statement : s.sid], "BedrockProfile")
    error_message = "No profile statement without a profile"
  }
}

run "endpoint_is_one_value" {
  command = apply # mocked: nothing reaches AWS

  assert {
    condition     = aws_lambda_function.guard.environment[0].variables.MODEL_ENDPOINT == "https://api.decisioncircuits.com/v1/systemone"
    error_message = "Lambda must read the endpoint from var.model_endpoint"
  }
  assert {
    condition     = contains([for s in data.aws_iam_policy_document.guard.statement : s.sid], "ModelApiKey")
    error_message = "An HTTPS endpoint needs the API-key secret"
  }
}

run "sagemaker_swaps_auth" {
  command = apply # mocked: nothing reaches AWS

  variables {
    model_endpoint = { url = "sagemaker://circuit-8b-endpoint", model = "circuit-8b" }
  }

  assert {
    condition     = contains([for s in data.aws_iam_policy_document.guard.statement : s.sid], "SageMakerModel")
    error_message = "A sagemaker:// endpoint needs sagemaker:InvokeEndpoint"
  }
  assert {
    condition     = !contains([for s in data.aws_iam_policy_document.guard.statement : s.sid], "ModelApiKey")
    error_message = "A sagemaker:// endpoint must not read the API-key secret"
  }
}

run "rejects_plain_http" {
  command = plan

  variables {
    model_endpoint = { url = "http://example.com/v1/systemone", model = "circuit-8b" }
  }

  expect_failures = [var.model_endpoint]
}
