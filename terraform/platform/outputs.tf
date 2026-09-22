output "ecr_repository_url" {
  description = "URL of the shared application ECR repository."
  value       = aws_ecr_repository.app.repository_url
}

output "platform_admin_access_key_id" {
  description = "Access key ID for the local platform administrator."
  value       = aws_iam_access_key.platform_admin.id
}

output "platform_admin_secret_access_key" {
  description = "Secret access key for the local platform administrator."
  value       = aws_iam_access_key.platform_admin.secret
  sensitive   = true
}

output "cluster_names" {
  description = "Names of the Kubernetes clusters managed by the platform."

  value = {
    management = module.management.cluster_name
    nonprod    = module.nonprod.cluster_name
    prod       = module.prod.cluster_name
  }
}

output "cluster_endpoints" {
  description = "Kubernetes API endpoints for the platform clusters."

  value = {
    management = module.management.cluster_endpoint
    nonprod    = module.nonprod.cluster_endpoint
    prod       = module.prod.cluster_endpoint
  }
}

output "vpc_ids" {
  description = "VPC IDs associated with each cluster."

  value = {
    management = module.management.vpc_id
    nonprod    = module.nonprod.vpc_id
    prod       = module.prod.vpc_id
  }
}
