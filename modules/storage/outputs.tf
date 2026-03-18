output "bucket_id" {
  description = "S3 bucket name (includes random suffix)"
  value       = aws_s3_bucket.logs.id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.logs.arn
}
