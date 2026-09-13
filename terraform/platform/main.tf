locals {
  common_tags = {
    Project   = "devops-platform-lab"
    ManagedBy = "terraform"
  }
}

module "management" {
  source = "../modules/eks-cluster"

  cluster_name = "devops-mgmt"
  environment  = "management"

  vpc_cidr      = "10.10.0.0/16"
  subnet_a_cidr = "10.10.1.0/24"
  subnet_b_cidr = "10.10.2.0/24"

  tags = local.common_tags

  depends_on = [
    aws_ecr_repository.app
  ]
}

module "nonprod" {
  source = "../modules/eks-cluster"

  cluster_name = "devops-nonprod"
  environment  = "nonprod"

  vpc_cidr      = "10.20.0.0/16"
  subnet_a_cidr = "10.20.1.0/24"
  subnet_b_cidr = "10.20.2.0/24"

  tags = local.common_tags

  depends_on = [
    aws_ecr_repository.app
  ]
}

module "prod" {
  source = "../modules/eks-cluster"

  cluster_name = "devops-prod"
  environment  = "prod"

  vpc_cidr      = "10.30.0.0/16"
  subnet_a_cidr = "10.30.1.0/24"
  subnet_b_cidr = "10.30.2.0/24"

  tags = local.common_tags

  depends_on = [
    aws_ecr_repository.app
  ]
}
