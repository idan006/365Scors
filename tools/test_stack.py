#!/usr/bin/env python3
"""Smoke-test the Terraform web application and inventory API.

By default the tool reads Terraform outputs from the current directory:

    python tools/test_stack.py

You can also pass URLs explicitly:

    python tools/test_stack.py --web-url http://example --api-url https://example/dev/inventory
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, asdict
from typing import Any


DEFAULT_REGION = "us-east-1"


@dataclass
class CheckResult:
    name: str
    ok: bool
    detail: str
    data: dict[str, Any] | None = None


def run_command(args: list[str], timeout: int = 60) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def read_terraform_outputs() -> dict[str, Any]:
    result = run_command(["terraform", "output", "-json"])
    if result.returncode != 0:
        raise RuntimeError(
            "terraform output -json failed. Apply the stack first or pass --web-url and --api-url.\n"
            f"{result.stderr.strip()}"
        )

    try:
        outputs = json.loads(result.stdout or "{}")
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Could not parse terraform output JSON: {exc}") from exc

    return {
        name: value.get("value")
        for name, value in outputs.items()
        if isinstance(value, dict) and "value" in value
    }


def http_get(url: str, timeout: int) -> tuple[int, str, dict[str, str]]:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "365ScoresTerraformSmokeTest/1.0",
            "Accept": "application/json,text/html,*/*",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read().decode("utf-8", errors="replace")
            return response.status, body, dict(response.headers.items())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        return exc.code, body, dict(exc.headers.items())


def check_web_url(web_url: str, timeout: int, retries: int, expected_text: str | None) -> CheckResult:
    last_detail = ""

    for attempt in range(1, retries + 1):
        try:
            status, body, headers = http_get(web_url, timeout)
            if 200 <= status < 400:
                if expected_text and expected_text not in body:
                    return CheckResult(
                        name="web_url",
                        ok=False,
                        detail=f"HTTP {status}, but expected text was not found: {expected_text}",
                        data={"url": web_url, "attempt": attempt},
                    )

                heading_match = re.search(r"<h1[^>]*>(.*?)</h1>", body, re.IGNORECASE | re.DOTALL)
                heading = re.sub(r"\s+", " ", heading_match.group(1)).strip() if heading_match else None

                return CheckResult(
                    name="web_url",
                    ok=True,
                    detail=f"HTTP {status}",
                    data={
                        "url": web_url,
                        "attempt": attempt,
                        "heading": heading,
                        "content_type": headers.get("Content-Type"),
                    },
                )

            last_detail = f"Attempt {attempt}: HTTP {status}"
        except Exception as exc:  # noqa: BLE001 - this is a CLI smoke-test boundary.
            last_detail = f"Attempt {attempt}: {exc}"

        if attempt < retries:
            time.sleep(10)

    return CheckResult(name="web_url", ok=False, detail=last_detail, data={"url": web_url})


def check_unsigned_api(api_url: str, timeout: int) -> CheckResult:
    try:
        status, body, _headers = http_get(api_url, timeout)
    except Exception as exc:  # noqa: BLE001 - this is a CLI smoke-test boundary.
        return CheckResult(name="api_unsigned_request", ok=False, detail=str(exc), data={"url": api_url})

    expected_auth_failure = status in {401, 403} and (
        "Missing Authentication Token" in body
        or "Forbidden" in body
        or "Unauthorized" in body
    )

    return CheckResult(
        name="api_unsigned_request",
        ok=expected_auth_failure,
        detail=f"HTTP {status}",
        data={
            "url": api_url,
            "expected": "401/403 because API Gateway uses AWS_IAM auth",
            "body_preview": body[:200],
        },
    )


def api_id_from_url(api_url: str) -> str:
    match = re.match(r"^https://([^.]+)\.execute-api\.[^.]+\.amazonaws\.com/", api_url)
    if not match:
        raise ValueError(f"Could not extract API Gateway REST API id from URL: {api_url}")
    return match.group(1)


def check_api_gateway_test_invoke(api_url: str, region: str) -> CheckResult:
    try:
        api_id = api_id_from_url(api_url)
    except ValueError as exc:
        return CheckResult(name="api_gateway_test_invoke", ok=False, detail=str(exc), data={"url": api_url})

    resource_result = run_command(
        [
            "aws",
            "apigateway",
            "get-resources",
            "--rest-api-id",
            api_id,
            "--region",
            region,
            "--query",
            "items[?path=='/inventory'].id | [0]",
            "--output",
            "text",
        ]
    )
    if resource_result.returncode != 0:
        return CheckResult(
            name="api_gateway_test_invoke",
            ok=False,
            detail="Could not resolve /inventory resource id",
            data={"stderr": resource_result.stderr.strip(), "api_id": api_id},
        )

    resource_id = resource_result.stdout.strip()
    if not resource_id or resource_id == "None":
        return CheckResult(
            name="api_gateway_test_invoke",
            ok=False,
            detail="API Gateway /inventory resource was not found",
            data={"api_id": api_id},
        )

    invoke_result = run_command(
        [
            "aws",
            "apigateway",
            "test-invoke-method",
            "--rest-api-id",
            api_id,
            "--resource-id",
            resource_id,
            "--http-method",
            "GET",
            "--region",
            region,
            "--query",
            "{status:status,latency:latency}",
            "--output",
            "json",
        ],
        timeout=120,
    )
    if invoke_result.returncode != 0:
        return CheckResult(
            name="api_gateway_test_invoke",
            ok=False,
            detail="AWS CLI test-invoke-method failed",
            data={"stderr": invoke_result.stderr.strip(), "api_id": api_id, "resource_id": resource_id},
        )

    try:
        payload = json.loads(invoke_result.stdout)
    except json.JSONDecodeError:
        payload = {"raw": invoke_result.stdout.strip()}

    status = payload.get("status")
    return CheckResult(
        name="api_gateway_test_invoke",
        ok=status == 200,
        detail=f"status {status}",
        data={"api_id": api_id, "resource_id": resource_id, **payload},
    )


def print_text(results: list[CheckResult]) -> None:
    for result in results:
        marker = "PASS" if result.ok else "FAIL"
        print(f"[{marker}] {result.name}: {result.detail}")
        if result.data:
            for key, value in result.data.items():
                print(f"  {key}: {value}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Smoke-test the Terraform web URL and inventory API.")
    parser.add_argument("--web-url", help="Application URL. Defaults to terraform output application_url.")
    parser.add_argument("--api-url", help="Inventory API URL. Defaults to terraform output inventory_api_url.")
    parser.add_argument("--region", default=DEFAULT_REGION, help=f"AWS region. Default: {DEFAULT_REGION}.")
    parser.add_argument("--timeout", type=int, default=20, help="HTTP timeout in seconds.")
    parser.add_argument("--retries", type=int, default=12, help="Web URL retry count.")
    parser.add_argument("--expected-text", help="Optional text expected in the web response body.")
    parser.add_argument(
        "--skip-aws-test-invoke",
        action="store_true",
        help="Skip AWS CLI API Gateway test-invoke-method.",
    )
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    web_url = args.web_url
    api_url = args.api_url

    if not web_url or not api_url:
        try:
            outputs = read_terraform_outputs()
        except RuntimeError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 2

        web_url = web_url or outputs.get("application_url")
        api_url = api_url or outputs.get("inventory_api_url")

    if not web_url:
        print("ERROR: Missing web URL. Pass --web-url or apply Terraform first.", file=sys.stderr)
        return 2
    if not api_url:
        print("ERROR: Missing API URL. Pass --api-url or apply Terraform first.", file=sys.stderr)
        return 2

    results = [
        check_web_url(web_url, args.timeout, args.retries, args.expected_text),
        check_unsigned_api(api_url, args.timeout),
    ]

    if not args.skip_aws_test_invoke:
        results.append(check_api_gateway_test_invoke(api_url, args.region))

    if args.json:
        print(json.dumps([asdict(result) for result in results], indent=2))
    else:
        print_text(results)

    return 0 if all(result.ok for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
