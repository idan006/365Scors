resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  lifecycle {
    precondition {
      condition     = length(var.public_subnet_cidrs) == 0 || length(var.public_subnet_cidrs) == var.availability_zone_count
      error_message = "public_subnet_cidrs must be empty or contain exactly availability_zone_count CIDR blocks."
    }

    precondition {
      condition     = length(var.private_subnet_cidrs) == 0 || length(var.private_subnet_cidrs) == var.availability_zone_count
      error_message = "private_subnet_cidrs must be empty or contain exactly availability_zone_count CIDR blocks."
    }

    precondition {
      condition     = var.min_size <= var.desired_capacity && var.desired_capacity <= var.max_size
      error_message = "desired_capacity must be between min_size and max_size."
    }

    precondition {
      condition     = !var.enable_https || local.create_dns
      error_message = "enable_https requires both domain_name and hosted_zone_id."
    }
  }

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  count = var.availability_zone_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.selected_azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count = var.availability_zone_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.private_subnet_cidrs[count.index]
  availability_zone       = local.selected_azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = var.availability_zone_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[var.single_nat_gateway ? 0 : count.index].id

  tags = {
    Name = "${local.name_prefix}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  count = var.availability_zone_count

  vpc_id = aws_vpc.this.id

  dynamic "route" {
    for_each = var.enable_nat_gateway ? [1] : []

    content {
      cidr_block     = "0.0.0.0/0"
      nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? 0 : count.index].id
    }
  }

  tags = {
    Name = "${local.name_prefix}-private-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "private" {
  count = var.availability_zone_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
