data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name       = "decide-in-code"
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  use_sagemaker      = startswith(var.model_endpoint.url, "sagemaker://")
  sagemaker_endpoint = trimprefix(var.model_endpoint.url, "sagemaker://")

  # A cross-region profile (us./global.) routes to the base model in several regions;
  # a bare model ID runs in this region only. IAM in iam.tf is scoped to exactly one of these.
  bedrock_uses_profile   = can(regex("^(us|eu|apac|global)\\.", var.bedrock_model_id))
  bedrock_profile_arn    = "arn:${local.partition}:bedrock:${var.region}:${local.account_id}:inference-profile/${var.bedrock_model_id}"
  bedrock_foundation_id  = replace(var.bedrock_model_id, "/^(us|eu|apac|global)\\./", "")
  bedrock_foundation_arn = "arn:${local.partition}:bedrock:${local.bedrock_uses_profile ? "*" : var.region}::foundation-model/${local.bedrock_foundation_id}"

  lambda_log_group = "/aws/lambda/${local.name}-guard"
  api_log_group    = "/aws/apigateway/${local.name}"
}

# ---- one customer-managed key for the secret, the queue and the logs ----

data "aws_iam_policy_document" "kms" {
  #checkov:skip=CKV_AWS_109:Key policy: "*" means this key; root delegates to IAM, the standard key policy.
  #checkov:skip=CKV_AWS_111:Key policy: "*" means this key; root delegates to IAM, the standard key policy.
  #checkov:skip=CKV_AWS_356:Key policy: "*" means this key; root delegates to IAM, the standard key policy.
  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:${local.lambda_log_group}",
        "arn:${local.partition}:logs:${var.region}:${local.account_id}:log-group:${local.api_log_group}",
      ]
    }
  }
}

resource "aws_kms_key" "main" {
  description             = "${local.name}: API key secret, human-review queue, logs"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "main" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.main.key_id
}

# ---- the model's API key: the secret exists, its value never enters Terraform ----

resource "aws_secretsmanager_secret" "model_api_key" {
  #checkov:skip=CKV2_AWS_57:A third-party API key cannot be rotated by a Lambda; rotate it at decisioncircuits.com and put-secret-value.
  name                    = "${local.name}/model-api-key"
  description             = "API key for ${var.model_endpoint.url}. Set with: aws secretsmanager put-secret-value"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 0 # teardown and redeploy on the same day without a name clash
}

# ---- human review ----

resource "aws_sqs_queue" "human_review" {
  name                      = "${local.name}-human-review"
  kms_master_key_id         = aws_kms_key.main.arn
  message_retention_seconds = 1209600 # 14 days: reviewers get back from vacation
}

# ---- logs ----

resource "aws_cloudwatch_log_group" "lambda" {
  #checkov:skip=CKV_AWS_338:Demo stack; 14 days by default, raise var.log_retention_days for real use.
  name              = local.lambda_log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn
}

resource "aws_cloudwatch_log_group" "api" {
  #checkov:skip=CKV_AWS_338:Demo stack; 14 days by default, raise var.log_retention_days for real use.
  name              = local.api_log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.main.arn
}
