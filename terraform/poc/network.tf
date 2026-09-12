resource "aws_vpc" "poc" {
  cidr_block = "10.10.0.0/16"

  tags = {
    Name        = "devops-poc-vpc"
    Environment = "poc"
  }
}

resource "aws_subnet" "eks_a" {
  vpc_id            = aws_vpc.poc.id
  cidr_block        = "10.10.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name        = "devops-poc-subnet-a"
    Environment = "poc"
  }
}

resource "aws_subnet" "eks_b" {
  vpc_id            = aws_vpc.poc.id
  cidr_block        = "10.10.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name        = "devops-poc-subnet-b"
    Environment = "poc"
  }
}
