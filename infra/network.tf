# Creates the isolated address space shared by EKS, databases, and analytics.
resource "aws_vpc" "library" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = local.name }
}

# Gives public subnets a route to AWS and the internet.
resource "aws_internet_gateway" "library" {
  vpc_id = aws_vpc.library.id
}

# Places internet-facing load balancers in both selected Availability Zones.
resource "aws_subnet" "public" {
  for_each          = local.zones
  vpc_id            = aws_vpc.library.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(aws_vpc.library.cidr_block, 8, each.value)
  tags = {
    Name                     = "${local.name}-public-${each.key}"
    "kubernetes.io/role/elb" = "1"
  }
}

# Places worker nodes and private compute in both selected Availability Zones.
resource "aws_subnet" "private" {
  for_each          = local.zones
  vpc_id            = aws_vpc.library.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(aws_vpc.library.cidr_block, 8, 10 + each.value)
  tags = {
    Name                              = "${local.name}-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Isolates database network interfaces from public and worker subnets.
resource "aws_subnet" "database" {
  for_each          = local.zones
  vpc_id            = aws_vpc.library.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(aws_vpc.library.cidr_block, 8, 20 + each.value)
  tags              = { Name = "${local.name}-database-${each.key}" }
}

# Holds the default internet route for public subnets.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.library.id
}

# Sends public subnet internet traffic through the internet gateway.
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.library.id
}

# Attaches each public subnet to its internet-facing route table.
resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# Reserves the stable public address used by the shared NAT gateway.
resource "aws_eip" "nat" {
  domain = "vpc"
}

# One NAT is a development cost/availability tradeoff; both private AZs share it.
resource "aws_nat_gateway" "library" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[var.availability_zones[0]].id
  depends_on    = [aws_internet_gateway.library]
}

# Holds the private subnet egress route while keeping nodes non-public.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.library.id
}

# Sends private worker egress through the cost-shared NAT gateway.
resource "aws_route" "private_internet" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.library.id
}

# Attaches each worker subnet to the private egress route table.
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# Database subnets have only the VPC-local route, with no internet/NAT default.
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.library.id
}

# Associates the isolated database subnets with the database-only route table.
resource "aws_route_table_association" "database" {
  for_each       = aws_subnet.database
  subnet_id      = each.value.id
  route_table_id = aws_route_table.database.id
}

# Keeps S3 and DynamoDB traffic on AWS's private network without NAT processing.
resource "aws_vpc_endpoint" "storage" {
  for_each          = toset(["s3", "dynamodb"])
  vpc_id            = aws_vpc.library.id
  service_name      = "com.amazonaws.${var.aws_region}.${each.key}"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}
