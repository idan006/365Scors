import json
from collections import defaultdict

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError


CLIENT_CONFIG = Config(retries={"max_attempts": 5, "mode": "standard"})


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Cache-Control": "no-store",
        },
        "body": json.dumps(body, default=str),
    }


def arn_service(arn):
    parts = arn.split(":", 5)
    return parts[2] if len(parts) > 2 else "unknown"


def tags_to_dict(tags):
    return {tag.get("Key"): tag.get("Value") for tag in tags or []}


def list_regions():
    ec2 = boto3.client("ec2", config=CLIENT_CONFIG)
    result = ec2.describe_regions(AllRegions=False)
    return sorted(region["RegionName"] for region in result["Regions"])


def list_taggable_resources(region_name):
    client = boto3.client(
        "resourcegroupstaggingapi",
        region_name=region_name,
        config=CLIENT_CONFIG,
    )
    paginator = client.get_paginator("get_resources")
    resources = []

    for page in paginator.paginate(ResourcesPerPage=100):
        for item in page.get("ResourceTagMappingList", []):
            arn = item.get("ResourceARN")
            resources.append(
                {
                    "arn": arn,
                    "service": arn_service(arn),
                    "region": region_name,
                    "tags": tags_to_dict(item.get("Tags")),
                }
            )

    return resources


def scan_inventory():
    inventory = {
        "services_by_region": {},
        "service_details": {},
        "errors": [],
    }

    for region_name in list_regions():
        try:
            resources = list_taggable_resources(region_name)
        except (BotoCoreError, ClientError) as exc:
            inventory["errors"].append(
                {
                    "region": region_name,
                    "error": str(exc),
                }
            )
            continue

        service_counts = defaultdict(int)
        service_details = defaultdict(list)

        for resource in resources:
            service = resource["service"]
            service_counts[service] += 1
            service_details[service].append(
                {
                    "arn": resource["arn"],
                    "tags": resource["tags"],
                }
            )

        inventory["services_by_region"][region_name] = [
            {"service": service, "resource_count": count}
            for service, count in sorted(service_counts.items())
        ]

        if service_details:
            inventory["service_details"][region_name] = {
                service: sorted(items, key=lambda item: item["arn"])
                for service, items in sorted(service_details.items())
            }

    return inventory


def handler(event, context):
    method = (
        event.get("httpMethod")
        or event.get("requestContext", {}).get("http", {}).get("method")
        or "GET"
    )

    if method != "GET":
        return response(405, {"message": "Method not allowed"})

    return response(200, scan_inventory())
