output "alb_dns_name" {
  description = "DNS name of the application load balancer."
  value       = aws_lb.this.dns_name
}

output "application_url" {
  description = "Best URL to open for the application."
  value = local.create_dns ? (
    local.create_https ? "https://${var.domain_name}" : "http://${var.domain_name}"
  ) : "http://${aws_lb.this.dns_name}"
}

output "route53_record_name" {
  description = "Custom domain record created in Route 53, if enabled."
  value       = local.create_dns ? aws_route53_record.app[0].fqdn : null
}

output "autoscaling_group_name" {
  description = "Name of the web Auto Scaling group."
  value       = aws_autoscaling_group.web.name
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets used by the ALB."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets used by EC2 instances."
  value       = aws_subnet.private[*].id
}

output "inventory_api_url" {
  description = "IAM-secured API endpoint for AWS service inventory."
  value       = "${aws_api_gateway_stage.inventory.invoke_url}/inventory"
}

output "waf_web_acl_arn" {
  description = "ARN of the WAF web ACL associated with the ALB, if enabled."
  value       = var.enable_waf ? aws_wafv2_web_acl.alb[0].arn : null
}
