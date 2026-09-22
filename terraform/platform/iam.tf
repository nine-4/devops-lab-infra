resource "aws_iam_user" "platform_admin" {
  name = "devops-platform-admin"

  tags = local.common_tags
}

resource "aws_iam_access_key" "platform_admin" {
  user = aws_iam_user.platform_admin.name
}
