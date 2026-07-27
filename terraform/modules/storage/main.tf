# Asset storage with cross-region replication. The application stores
# exported note attachments here; the interesting part for the DR story
# is that every object written in the primary region shows up in the
# secondary bucket within minutes, without any action at failover time.
# Unlike the database there is nothing to promote: the secondary bucket
# is always readable and writable.

data "aws_caller_identity" "current" {
  provider = aws.primary
}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket" "primary" {
  provider = aws.primary

  bucket = "${var.name}-assets-${local.account_id}-primary"
}

resource "aws_s3_bucket" "secondary" {
  provider = aws.secondary

  bucket = "${var.name}-assets-${local.account_id}-secondary"
}

# Versioning is a hard requirement of S3 replication on both sides, and
# it doubles as protection against accidental deletes.
resource "aws_s3_bucket_versioning" "primary" {
  provider = aws.primary

  bucket = aws_s3_bucket.primary.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_versioning" "secondary" {
  provider = aws.secondary

  bucket = aws_s3_bucket.secondary.id
  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 rather than KMS: replicating KMS encrypted objects requires
# extra grants on both keys and buys little for public-ish demo assets.
# The trade-off is called out in the security pillar of the review.
resource "aws_s3_bucket_server_side_encryption_configuration" "primary" {
  provider = aws.primary

  bucket = aws_s3_bucket.primary.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "secondary" {
  provider = aws.secondary

  bucket = aws_s3_bucket.secondary.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "primary" {
  provider = aws.primary

  bucket                  = aws_s3_bucket.primary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "secondary" {
  provider = aws.secondary

  bucket                  = aws_s3_bucket.secondary.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "replication_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  provider = aws.primary

  name               = "${var.name}-s3-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume.json
}

data "aws_iam_policy_document" "replication" {
  statement {
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = [aws_s3_bucket.primary.arn]
  }

  statement {
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.primary.arn}/*"]
  }

  statement {
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]
    resources = ["${aws_s3_bucket.secondary.arn}/*"]
  }
}

resource "aws_iam_role_policy" "replication" {
  provider = aws.primary

  name   = "${var.name}-s3-replication"
  role   = aws_iam_role.replication.id
  policy = data.aws_iam_policy_document.replication.json
}

resource "aws_s3_bucket_replication_configuration" "primary_to_secondary" {
  provider = aws.primary

  bucket = aws_s3_bucket.primary.id
  role   = aws_iam_role.replication.arn

  rule {
    id     = "everything-to-secondary"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = aws_s3_bucket.secondary.arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.primary,
    aws_s3_bucket_versioning.secondary,
  ]
}
