data "aws_caller_identity" "current" {}

locals {
  site_dir   = "${path.module}/.."
  bucket     = "alpfr-com-site-${data.aws_caller_identity.current.account_id}"
  hostnames  = [var.domain_name, "www.${var.domain_name}"]
  use_r53    = var.enable_custom_domain && var.route53_zone_id != ""

  # Files published to the site. Add new pages or assets here.
  site_files = {
    "index.html"                 = "text/html; charset=utf-8"
    "capabilities-statement.pdf" = "application/pdf"
  }
}

# ---------- Storage (private; only CloudFront can read it) ----------

resource "aws_s3_bucket" "site" {
  bucket = local.bucket

  # The bucket only holds files that are also in this folder, so destroy.sh may empty it.
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "site" {
  for_each = local.site_files

  bucket       = aws_s3_bucket.site.id
  key          = each.key
  source       = "${local.site_dir}/${each.key}"
  etag         = filemd5("${local.site_dir}/${each.key}")
  content_type = each.value
  # CloudFront honors this, so an updated file reaches visitors within 5 minutes
  # without a cache invalidation.
  cache_control = "public,max-age=300"
}

data "aws_iam_policy_document" "site" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket     = aws_s3_bucket.site.id
  policy     = data.aws_iam_policy_document.site.json
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# ---------- CloudFront ----------

data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "alpfr-com-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  comment             = "alpfr.com static site"
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = var.enable_custom_domain ? local.hostnames : []

  origin {
    origin_id                = "s3-site"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "s3-site"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = !var.enable_custom_domain
    acm_certificate_arn            = var.enable_custom_domain ? aws_acm_certificate_validation.site[0].certificate_arn : null
    ssl_support_method             = var.enable_custom_domain ? "sni-only" : null
    minimum_protocol_version       = var.enable_custom_domain ? "TLSv1.2_2021" : "TLSv1"
  }
}

# ---------- Custom domain (only when enable_custom_domain = true) ----------

resource "aws_acm_certificate" "site" {
  count = var.enable_custom_domain ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# With Route 53: validation records are created for you.
resource "aws_route53_record" "cert_validation" {
  for_each = local.use_r53 ? {
    for o in aws_acm_certificate.site[0].domain_validation_options : o.domain_name => o
  } : {}

  zone_id         = var.route53_zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

# Waits until the certificate is issued. Without Route 53, add the records shown by
# `terraform output certificate_validation_records` at your DNS host while this waits.
resource "aws_acm_certificate_validation" "site" {
  count = var.enable_custom_domain ? 1 : 0

  certificate_arn         = aws_acm_certificate.site[0].arn
  validation_record_fqdns = local.use_r53 ? [for r in aws_route53_record.cert_validation : r.fqdn] : null
}

# With Route 53: point alpfr.com and www.alpfr.com at the distribution. THIS IS THE CUTOVER.
resource "aws_route53_record" "site" {
  for_each = local.use_r53 ? { for pair in setproduct(local.hostnames, ["A", "AAAA"]) : "${pair[0]}-${pair[1]}" => pair } : {}

  zone_id         = var.route53_zone_id
  name            = each.value[0]
  type            = each.value[1]
  allow_overwrite = true

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
