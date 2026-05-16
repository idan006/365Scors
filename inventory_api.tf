data "archive_file" "inventory_api" {
  type        = "zip"
  source_file = "${path.module}/lambda/aws_inventory_api.py"
  output_path = "${path.module}/.lambda_build/aws_inventory_api.zip"
}

resource "aws_iam_role" "inventory_api_lambda" {
  name = "${local.name_prefix}-inventory-api-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-inventory-api-lambda"
  }
}

resource "aws_iam_role_policy_attachment" "inventory_api_logs" {
  role       = aws_iam_role.inventory_api_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "inventory_api_read_only" {
  role       = aws_iam_role.inventory_api_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_lambda_function" "inventory_api" {
  function_name    = "${local.name_prefix}-inventory-api"
  role             = aws_iam_role.inventory_api_lambda.arn
  runtime          = "python3.12"
  handler          = "aws_inventory_api.handler"
  filename         = data.archive_file.inventory_api.output_path
  source_code_hash = data.archive_file.inventory_api.output_base64sha256
  timeout          = 60
  memory_size      = 256

  depends_on = [
    aws_iam_role_policy_attachment.inventory_api_logs,
    aws_iam_role_policy_attachment.inventory_api_read_only,
  ]

  tags = {
    Name = "${local.name_prefix}-inventory-api"
  }
}

resource "aws_api_gateway_rest_api" "inventory" {
  name        = "${local.name_prefix}-inventory-api"
  description = "Secured API for listing AWS services and resources by region."

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = {
    Name = "${local.name_prefix}-inventory-api"
  }
}

resource "aws_api_gateway_resource" "inventory" {
  rest_api_id = aws_api_gateway_rest_api.inventory.id
  parent_id   = aws_api_gateway_rest_api.inventory.root_resource_id
  path_part   = "inventory"
}

resource "aws_api_gateway_method" "inventory_get" {
  rest_api_id   = aws_api_gateway_rest_api.inventory.id
  resource_id   = aws_api_gateway_resource.inventory.id
  http_method   = "GET"
  authorization = "AWS_IAM"
}

resource "aws_api_gateway_integration" "inventory_get" {
  rest_api_id             = aws_api_gateway_rest_api.inventory.id
  resource_id             = aws_api_gateway_resource.inventory.id
  http_method             = aws_api_gateway_method.inventory_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.inventory_api.invoke_arn
}

resource "aws_lambda_permission" "allow_api_gateway_inventory" {
  statement_id  = "AllowInventoryApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inventory_api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.inventory.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "inventory" {
  rest_api_id = aws_api_gateway_rest_api.inventory.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.inventory.id,
      aws_api_gateway_method.inventory_get.id,
      aws_api_gateway_integration.inventory_get.id,
      aws_lambda_function.inventory_api.source_code_hash,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.inventory_get,
  ]
}

resource "aws_api_gateway_stage" "inventory" {
  rest_api_id   = aws_api_gateway_rest_api.inventory.id
  deployment_id = aws_api_gateway_deployment.inventory.id
  stage_name    = var.environment

  tags = {
    Name = "${local.name_prefix}-inventory-api"
  }
}
