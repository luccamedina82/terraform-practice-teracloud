# Bucket to store Terraform state files
resource "aws_s3_bucket" "terraform_state" {
  bucket = "teracloud-terraform-state"

  # Avoid accidental deletion of the bucket that holds all remote state
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}
