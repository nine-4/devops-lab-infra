variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "environment" {
  description = "Environment or platform boundary represented by this cluster."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block assigned to the cluster VPC."
  type        = string
}

variable "subnet_a_cidr" {
  description = "CIDR block for the first EKS subnet."
  type        = string
}

variable "subnet_b_cidr" {
  description = "CIDR block for the second EKS subnet."
  type        = string
}

variable "availability_zone_a" {
  description = "Availability zone for the first EKS subnet."
  type        = string
  default     = "us-east-1a"
}

variable "availability_zone_b" {
  description = "Availability zone for the second EKS subnet."
  type        = string
  default     = "us-east-1b"
}

variable "tags" {
  description = "Additional tags to apply to resources created by this module."
  type        = map(string)
  default     = {}
}
