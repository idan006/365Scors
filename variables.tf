variable "aws_region" {
  description = "AWS region where the infrastructure will be created."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name used to prefix AWS resources."
  type        = string
  default     = "simple-webapp"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zone_count" {
  description = "Number of availability zones and public subnets to use."
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zone_count >= 2
    error_message = "Use at least two availability zones for the load balancer."
  }
}

variable "public_subnet_cidrs" {
  description = "Optional explicit CIDR blocks for public subnets. Leave empty to auto-calculate."
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "Optional explicit CIDR blocks for private application subnets. Leave empty to auto-calculate."
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "When true, create NAT Gateway egress so private EC2 instances can reach the internet for updates."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "When true, create one NAT Gateway for all private subnets. Lower cost, less resilient than one per AZ."
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "When true, publish VPC Flow Logs to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "instance_type" {
  description = "EC2 instance type for the web servers."
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Optional existing EC2 key pair name for SSH access."
  type        = string
  default     = null
}

variable "allowed_http_cidr_blocks" {
  description = "CIDR blocks allowed to reach the load balancer over HTTP and HTTPS."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_ssh_cidr_blocks" {
  description = "CIDR blocks allowed to SSH to EC2 instances. Empty disables inbound SSH."
  type        = list(string)
  default     = []
}

variable "app_port" {
  description = "Port the web app listens on inside each EC2 instance."
  type        = number
  default     = 80
}

variable "enable_backend_tls" {
  description = "When true, the ALB connects to EC2 instances over HTTPS using a self-signed nginx certificate."
  type        = bool
  default     = false
}

variable "min_size" {
  description = "Minimum number of EC2 instances."
  type        = number
  default     = 2
}

variable "desired_capacity" {
  description = "Desired number of EC2 instances."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of EC2 instances."
  type        = number
  default     = 2
}

variable "enable_asg_cpu_scaling" {
  description = "When true, attach target-tracking CPU scaling to the Auto Scaling group."
  type        = bool
  default     = true
}

variable "asg_target_cpu_utilization" {
  description = "Average ASG CPU percentage that target-tracking scaling should maintain."
  type        = number
  default     = 50
}

variable "health_check_path" {
  description = "Path used by the ALB target group health check."
  type        = string
  default     = "/"
}

variable "domain_name" {
  description = "Optional fully qualified custom domain name, such as app.example.com. Leave empty to skip DNS."
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Optional Route 53 hosted zone ID that contains domain_name."
  type        = string
  default     = ""
}

variable "enable_https" {
  description = "When true, create and validate an ACM certificate and expose the ALB on HTTPS."
  type        = bool
  default     = false
}

variable "enable_deletion_protection" {
  description = "When true, enable ALB deletion protection. Recommended for production environments."
  type        = bool
  default     = false
}

variable "certificate_domain_name" {
  description = "Optional certificate name. Defaults to domain_name when blank."
  type        = string
  default     = ""
}

variable "enable_waf" {
  description = "When true, attach an AWS WAFv2 web ACL with AWS managed rule groups to the ALB."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days for Lambda, API Gateway, and VPC Flow Logs."
  type        = number
  default     = 30
}

variable "api_throttle_rate_limit" {
  description = "API Gateway steady-state request rate limit per second."
  type        = number
  default     = 20
}

variable "api_throttle_burst_limit" {
  description = "API Gateway burst request limit."
  type        = number
  default     = 40
}

variable "lambda_reserved_concurrent_executions" {
  description = "Reserved concurrency for the inventory Lambda. Use -1 for unreserved concurrency."
  type        = number
  default     = -1
}

variable "alarm_actions" {
  description = "Optional SNS topic ARNs or other action ARNs notified by CloudWatch alarms."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all supported resources."
  type        = map(string)
  default     = {}
}
