resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  tags = merge(
    var.tags,
    {
      Name        = "${var.cluster_name}-vpc"
      Environment = var.environment
    }
  )
}

resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_a_cidr
  availability_zone = var.availability_zone_a

  tags = merge(
    var.tags,
    {
      Name        = "${var.cluster_name}-subnet-a"
      Environment = var.environment
    }
  )
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_b_cidr
  availability_zone = var.availability_zone_b

  tags = merge(
    var.tags,
    {
      Name        = "${var.cluster_name}-subnet-b"
      Environment = var.environment
    }
  )
}
