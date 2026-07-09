data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# 1. VPC Definition
# -----------------------------------------------------------------------------
resource "aws_vpc" "databricks_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-databricks-vpc"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# 2. Subnets Definition (Public & Private)
# -----------------------------------------------------------------------------
resource "aws_subnet" "public_subnets" {
  count                   = 2
  vpc_id                  = aws_vpc.databricks_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 3, count.index) # 10.0.0.0/19, 10.0.32.0/19
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index}"
    Environment = var.environment
  }
}

resource "aws_subnet" "private_subnets" {
  count             = 2
  vpc_id            = aws_vpc.databricks_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 3, count.index + 2) # 10.0.64.0/19, 10.0.96.0/19
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index}"
    Environment = var.environment
    # Required tagging for Databricks workspace network binding
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# -----------------------------------------------------------------------------
# 3. Internet Gateway & NAT Gateways (Egress)
# -----------------------------------------------------------------------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.databricks_vpc.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]

  tags = {
    Name        = "${var.project_name}-nat-eip"
    Environment = var.environment
  }
}

resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnets[0].id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name        = "${var.project_name}-nat-gw"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# 4. Route Tables & Subnet Associations
# -----------------------------------------------------------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.databricks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.databricks_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw
  }

  tags = {
    Name        = "${var.project_name}-private-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public_assoc" {
  count          = 2
  subnet_id      = aws_subnet.public_subnets[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_assoc" {
  count          = 2
  subnet_id      = aws_subnet.private_subnets[count.index].id
  route_table_id = aws_route_table.private_rt.id
}

# -----------------------------------------------------------------------------
# 5. VPC Endpoints (S3 & STS)
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.databricks_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_rt.id]

  tags = {
    Name        = "${var.project_name}-s3-vpc-endpoint"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# 5b. VPC Interface Endpoint (STS)
# Databricks requires STS for IAM role assumption. Without this endpoint,
# STS calls route through the NAT Gateway, adding latency and cost.
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "sts" {
  vpc_id              = aws_vpc.databricks_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private_subnets[*].id
  security_group_ids  = [aws_security_group.databricks_sg.id]
  private_dns_enabled = true

  tags = {
    Name        = "${var.project_name}-sts-vpc-endpoint"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# 6. Databricks Default Security Group
# -----------------------------------------------------------------------------
# Requires rules permitting internal communication between master and worker nodes.
resource "aws_security_group" "databricks_sg" {
  name        = "${var.project_name}-databricks-sg"
  description = "Default Security Group for Databricks Clusters in VPC"
  vpc_id      = aws_vpc.databricks_vpc.id

  # Ingress: Allow all communication internally within the Security Group
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Egress: Allow all outbound traffic
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name        = "${var.project_name}-databricks-sg"
    Environment = var.environment
  }
}
