# Static website hosting with Cognito Identity Pool for browser SigV4 signing.

# S3 bucket for static content
resource "aws_s3_bucket" "web" {
  bucket_prefix = "${local.name}-web-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "web" {
  bucket                  = aws_s3_bucket.web.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "web" {
  name                              = local.name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  comment             = "${local.name} demo GUI"

  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id                = "s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  default_cache_behavior {
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 300
    max_ttl     = 3600
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = var.tags
}

# S3 bucket policy for CloudFront
resource "aws_s3_bucket_policy" "web" {
  bucket = aws_s3_bucket.web.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontAccess"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.web.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.web.arn
        }
      }
    }]
  })
}

# Cognito Identity Pool for browser credentials
resource "aws_cognito_identity_pool" "web" {
  identity_pool_name               = replace(local.name, "-", " ")
  allow_unauthenticated_identities = true
  allow_classic_flow               = false

  tags = var.tags
}

# IAM role for unauthenticated users
resource "aws_iam_role" "cognito_unauth" {
  name = "${local.name}-cognito-unauth"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "cognito-identity.amazonaws.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.web.id
        }
        "ForAnyValue:StringLike" = {
          "cognito-identity.amazonaws.com:amr" = "unauthenticated"
        }
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cognito_unauth" {
  name = "invoke-api"
  role = aws_iam_role.cognito_unauth.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "execute-api:Invoke"
      Resource = "${aws_apigatewayv2_api.guard.execution_arn}/*/POST/messages"
    }]
  })
}

# Attach role to identity pool
resource "aws_cognito_identity_pool_roles_attachment" "web" {
  identity_pool_id = aws_cognito_identity_pool.web.id

  roles = {
    unauthenticated = aws_iam_role.cognito_unauth.arn
  }
}

# Upload index.html to S3 with config injected
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.web.id
  key          = "index.html"
  content_type = "text/html"
  content = replace(
    replace(
      replace(
        file("${path.module}/../gui/index-aws.html"),
        "{{REGION}}", var.region
      ),
      "{{IDENTITY_POOL_ID}}", aws_cognito_identity_pool.web.id
    ),
    "{{API_URL}}", "https://${aws_apigatewayv2_api.guard.id}.execute-api.${var.region}.amazonaws.com/messages"
  )
  etag = md5(replace(
    replace(
      replace(
        file("${path.module}/../gui/index-aws.html"),
        "{{REGION}}", var.region
      ),
      "{{IDENTITY_POOL_ID}}", aws_cognito_identity_pool.web.id
    ),
    "{{API_URL}}", "https://${aws_apigatewayv2_api.guard.id}.execute-api.${var.region}.amazonaws.com/messages"
  ))
}

# Outputs
output "web_url" {
  value       = "https://${aws_cloudfront_distribution.web.domain_name}"
  description = "CloudFront URL for the demo GUI"
}

output "identity_pool_id" {
  value       = aws_cognito_identity_pool.web.id
  description = "Cognito Identity Pool ID for browser credentials"
}
