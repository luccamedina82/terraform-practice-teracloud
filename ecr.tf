resource "aws_ecr_repository" "game" {
  name                 = "${var.game_name}-${local.name}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "ecr-${var.game_name}-${local.name}"
  }
}
