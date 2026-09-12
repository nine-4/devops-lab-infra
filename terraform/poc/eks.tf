resource "aws_eks_cluster" "poc" {
  name     = "devops-poc"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.eks_a.id,
      aws_subnet.eks_b.id
    ]
  }

  depends_on = [
    aws_ecr_repository.app
  ]
}
