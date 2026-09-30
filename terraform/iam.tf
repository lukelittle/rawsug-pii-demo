# The guard Lambda's role: exactly what the handler calls, on exactly these resources.

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
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

  # Reviewer summary (Converse = bedrock:InvokeModel). Through a cross-region
  # profile: the profile, plus the base model in its destination regions only
  # when the call comes through that one profile. Without one: the base model here.
  dynamic "statement" {
    for_each = local.bedrock_uses_profile ? [1] : []
    content {
      sid       = "BedrockProfile"
      actions   = ["bedrock:InvokeModel"]
      resources = [local.bedrock_profile_arn]
    }
  }

  statement {
    sid       = "BedrockModel"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.bedrock_foundation_arn]

    dynamic "condition" {
      for_each = local.bedrock_uses_profile ? [1] : []
      content {
        test     = "StringEquals"
        variable = "bedrock:InferenceProfileArn"
        values   = [local.bedrock_profile_arn]
      }
    }
  }
}

resource "aws_iam_role_policy" "guard" {
  name   = "${local.name}-guard"
  role   = aws_iam_role.guard.id
  policy = data.aws_iam_policy_document.guard.json
}
