variable "tags" {
  description = "Applied to every taggable resource (provider default_tags). Ippon policy: project, owner, customer."
  type        = map(string)
  default = {
    project  = "rawsug-pii-demo"
    owner    = "llittle@ippon.fr"
    customer = "training"
  }

  validation {
    condition     = alltrue([for k in ["project", "owner", "customer"] : trimspace(lookup(var.tags, k, "")) != ""])
    error_message = "tags must include non-empty project, owner and customer."
  }
  validation {
    condition     = can(regex("^([A-Za-z0-9._%+-]+@(ippon\\.fr|ipponusa\\.com)|slack://.+)$", lookup(var.tags, "owner", "")))
    error_message = "tags.owner must be an ippon.fr or ipponusa.com email address, or a slack:// URL."
  }
}

variable "region" {
  description = "AWS region for everything in this stack."
  type        = string
  default     = "us-east-1"
}

variable "model_endpoint" {
  description = <<-EOT
    Where the circuit's questions are answered. Change `url` (and `model`) to swap servers:
      hosted circuit  { url = "https://api.decisioncircuits.com/v1/systemone", model = "circuit-8b" }
      TypeSafe's Jev  { url = "https://api.typesafe.ai/v1/systemone",          model = "jev-latest" }
      SageMaker       { url = "sagemaker://<endpoint-name>",                     model = "circuit-8b" }
    HTTPS servers read their API key from the Secrets Manager secret; SageMaker uses IAM.
  EOT
  type = object({
    url   = string
    model = string
  })
  default = {
    url   = "https://api.decisioncircuits.com/v1/systemone"
    model = "circuit-8b"
  }

  validation {
    condition     = can(regex("^(https://|sagemaker://[A-Za-z0-9-]+$)", var.model_endpoint.url))
    error_message = "model_endpoint.url must be https://... or sagemaker://<endpoint-name>."
  }
}

variable "bedrock_model_id" {
  description = <<-EOT
    Bedrock model for the reviewer summary, called with the Converse API.
    A cross-region profile (us./global. prefix) or an in-region base model ID both work;
    IAM is scoped to whichever you pick. Default: Amazon Nova 2 Lite via the US profile
    (us-east-1 serves Nova 2 Lite only through cross-region profiles).
  EOT
  type        = string
  default     = "us.amazon.nova-2-lite-v1:0"

  validation {
    condition     = can(regex("^((us|eu|apac|global)\\.)?[a-z0-9-]+\\.[a-z0-9.:-]+$", var.bedrock_model_id))
    error_message = "Use a Bedrock model ID (amazon.nova-lite-v1:0) or inference profile ID (us.amazon.nova-2-lite-v1:0)."
  }
}

variable "log_retention_days" {
  description = "CloudWatch retention for the Lambda and API access logs."
  type        = number
  default     = 14
}

variable "throttle_rate" {
  description = "Steady-state requests per second for the API stage."
  type        = number
  default     = 5
}

variable "throttle_burst" {
  description = "Burst requests for the API stage."
  type        = number
  default     = 10
}
