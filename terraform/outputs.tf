output "api_url" {
  description = "POST {\"message\": \"...\"} here, SigV4-signed (see scripts/demo.sh)."
  value       = "${aws_apigatewayv2_api.guard.api_endpoint}/messages"
}

output "function_name" {
  value = aws_lambda_function.guard.function_name
}

output "review_queue_url" {
  value = aws_sqs_queue.human_review.url
}

output "api_key_secret_id" {
  description = "Put the model API key here (value never enters Terraform)."
  value       = aws_secretsmanager_secret.model_api_key.id
}

output "lambda_log_group" {
  value = aws_cloudwatch_log_group.lambda.name
}

output "region" {
  value = var.region
}
