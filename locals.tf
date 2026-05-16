locals {
  name_prefix = "${var.project_name}-${var.environment}"

  selected_azs = slice(data.aws_availability_zones.available.names, 0, var.availability_zone_count)

  public_subnet_cidrs = length(var.public_subnet_cidrs) > 0 ? var.public_subnet_cidrs : [
    for index in range(var.availability_zone_count) : cidrsubnet(var.vpc_cidr, 8, index)
  ]

  private_subnet_cidrs = length(var.private_subnet_cidrs) > 0 ? var.private_subnet_cidrs : [
    for index in range(var.availability_zone_count) : cidrsubnet(var.vpc_cidr, 8, index + var.availability_zone_count)
  ]

  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : var.availability_zone_count) : 0

  create_dns     = var.domain_name != "" && var.hosted_zone_id != ""
  create_https   = local.create_dns && var.enable_https
  certificate_cn = var.certificate_domain_name != "" ? var.certificate_domain_name : var.domain_name
  backend_port   = var.enable_backend_tls ? 443 : var.app_port
  backend_proto  = var.enable_backend_tls ? "HTTPS" : "HTTP"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    },
    var.tags
  )
}
