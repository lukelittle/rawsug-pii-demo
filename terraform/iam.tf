# The guard Lambda's role: exactly what the handler calls, on exactly these resources.

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "guard" {
  name               = "${local.name}-guard"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "guard" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid       = "XRay"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"] # X-Ray has no resource-level permissions
  }

  dynamic "statement" {
    for_each = local.use_sagemaker ? [] : [1]
    content {
      sid       = "ModelApiKey"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [aws_secretsmanager_secret.model_api_key.arn]
    }
  }

  dynamic "statement" {
    for_each = local.use_sagemaker ? [1] : []
    content {
      sid       = "SageMakerModel"
      actions   = ["sagemaker:InvokeEndpoint"]
      resources = ["arn:${local.partition}:sagemaker:${var.region}:${local.account_id}:endpoint/${lower(local.sagemaker_endpoint)}"]
    }
  }

  statement {
    sid       = "HumanReviewQueue"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.human_review.arn]
  }

  statement {
    sid       = "KmsForSecretAndQueue"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.main.arn]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.region}.amazonaws.com", "sqs.${var.region}.amazonaws.com"]
    }
  }

  # A US cross-region profile routes to several regions; allow the base model
  # there only when the call comes through this one profile.
  statement {
    sid       = "BedrockProfile"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.bedrock_profile_arn]
  }

  statement {
    sid       = "BedrockModelViaProfile"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.bedrock_foundation_arn]
    condition {
      test     = "StringEquals"
      variable = "bedrock:InferenceProfileArn"
      values   = [local.bedrock_profile_arn]
    }
  }
}

resource "aws_iam_role_policy" "guard" {
  name   = "${local.name}-guard"
  role   = aws_iam_role.guard.id
  policy = data.aws_iam_policy_document.guard.json
}
