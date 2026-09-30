# Function code is just lambda/*.py (a few KB), zipped here, so editing
# lambda/circuit.py and running `terraform apply` is the whole redeploy.
# Dependencies live in a layer built once by scripts/build-layer.sh.

data "archive_file" "function" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/../build/function.zip"
  excludes    = ["__pycache__"]
}

data "archive_file" "layer" {
  type        = "zip"
  source_dir  = "${path.module}/../build/layer"
  output_path = "${path.module}/../build/layer.zip"
}

resource "aws_lambda_layer_version" "deps" {
  layer_name               = "${local.name}-deps"
  description              = "decision-circuits (see layer/requirements.txt)"
  filename                 = data.archive_file.layer.output_path
  source_code_hash         = data.archive_file.layer.output_base64sha256
  compatible_runtimes      = ["python3.13"]
  compatible_architectures = ["arm64"]
}

resource "aws_lambda_function" "guard" {
  #checkov:skip=CKV_AWS_117:No private resources to reach; a VPC would add a NAT gateway for two public APIs.
  #checkov:skip=CKV_AWS_116:Invoked synchronously by API Gateway; failures return to the caller, and uncertain messages go to SQS.
  #checkov:skip=CKV_AWS_115:Reserved concurrency fails on accounts with the default limit of 10; the API stage throttles instead.
  #checkov:skip=CKV_AWS_272:Code signing would block the on-stage edit-and-apply loop this demo exists to show.
  #checkov:skip=CKV_AWS_173:Environment holds only URLs, names and ARNs; the API key is in Secrets Manager.
  function_name    = "${local.name}-guard"
  description      = "Decision circuit guard: redact / route / human review"
  role             = aws_iam_role.guard.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "handler.handler"
  filename         = data.archive_file.function.output_path
  source_code_hash = data.archive_file.function.output_base64sha256
  layers           = [aws_lambda_layer_version.deps.arn]
  memory_size      = 512
  timeout          = 300 # warmup waits out a cold model; API calls give up well inside API Gateway's 30s

  environment {
    variables = {
      MODEL_ENDPOINT     = var.model_endpoint.url
      MODEL_NAME         = var.model_endpoint.model
      API_KEY_SECRET_ARN = local.use_sagemaker ? "" : aws_secretsmanager_secret.model_api_key.arn
      BEDROCK_MODEL_ID   = var.bedrock_model_id
      REVIEW_QUEUE_URL   = aws_sqs_queue.human_review.url
    }
  }

  tracing_config {
    mode = "Active"
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.lambda.name
  }

  depends_on = [aws_iam_role_policy.guard]
}
