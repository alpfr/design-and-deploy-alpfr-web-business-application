output "preview_url" {
  description = "Always works, with or without the custom domain."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "distribution_id" {
  value = aws_cloudfront_distribution.site.id
}

output "bucket" {
  value = aws_s3_bucket.site.id
}

output "certificate_validation_records" {
  description = "Add these at your DNS host if it is not Route 53."
  value = var.enable_custom_domain ? [
    for o in aws_acm_certificate.site[0].domain_validation_options : {
      name  = o.resource_record_name
      type  = o.resource_record_type
      value = o.resource_record_value
    }
  ] : []
}
