output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "eks_cluster_name" {
  value = aws_eks_cluster.poc.name
}

output "eks_admin_access_key_id" {
  value = aws_iam_access_key.eks_admin.id
}

output "eks_admin_secret_access_key" {
  value     = aws_iam_access_key.eks_admin.secret
  sensitive = true
}
