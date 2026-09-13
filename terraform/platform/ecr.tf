resource "aws_ecr_repository" "app" {
  name         = "devops-lab-app"
  force_delete = true

  tags = local.common_tags
}
