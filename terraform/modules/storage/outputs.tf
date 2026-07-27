output "primary_bucket" {
  value = aws_s3_bucket.primary.bucket
}

output "secondary_bucket" {
  value = aws_s3_bucket.secondary.bucket
}

output "primary_bucket_arn" {
  value = aws_s3_bucket.primary.arn
}

output "secondary_bucket_arn" {
  value = aws_s3_bucket.secondary.arn
}
