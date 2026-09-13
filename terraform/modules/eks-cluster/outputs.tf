output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint exposed by the EKS cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "vpc_id" {
  description = "ID of the VPC created for the cluster."
  value       = aws_vpc.this.id
}

output "subnet_ids" {
  description = "IDs of the subnets assigned to the EKS cluster."

  value = [
    aws_subnet.a.id,
    aws_subnet.b.id
  ]
}

output "cluster_role_arn" {
  description = "ARN of the IAM role used by the EKS cluster."
  value       = aws_iam_role.eks_cluster.arn
}
