"""
Worker Service — eks-gitops-platform

Long-running Kubernetes Deployment that:
  - Polls SQS for messages published by the API service
  - Processes each message (simulates CPU/IO work)
  - Updates item status in DynamoDB (pending → processing → completed/failed)
  - Publishes custom CloudWatch metrics for KEDA to use for autoscaling
  - Handles graceful shutdown on SIGTERM (Kubernetes pod termination)

KEDA ScaledObject watches the SQS queue depth and scales this Deployment
from 0 to N replicas based on message volume. When the queue is empty,
this service scales to 0 — zero cost, zero idle workers.

All AWS credentials come from IRSA. No static keys.
"""

import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Structured JSON logging for CloudWatch Logs Insights
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}',
    stream=sys.stdout,
)
logger = logging.getLogger("worker-service")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
AWS_REGION        = os.environ.get("AWS_REGION", "us-east-1")
SQS_QUEUE_URL     = os.environ["SQS_QUEUE_URL"]
DYNAMODB_TABLE    = os.environ["DYNAMODB_TABLE"]
ENVIRONMENT       = os.environ.get("ENVIRONMENT", "prod")
POLL_WAIT_SECONDS = int(os.environ.get("POLL_WAIT_SECONDS", "20"))  # SQS long-poll
MAX_MESSAGES      = int(os.environ.get("MAX_MESSAGES", "10"))
WORKER_ID         = os.environ.get("HOSTNAME", "worker-unknown")

# ---------------------------------------------------------------------------
# AWS clients
# ---------------------------------------------------------------------------
sqs      = boto3.client("sqs",      region_name=AWS_REGION)
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
cw       = boto3.client("cloudwatch", region_name=AWS_REGION)
table    = dynamodb.Table(DYNAMODB_TABLE)

# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------
shutdown_requested = False

def handle_sigterm(signum, frame):
    global shutdown_requested
    logger.info("SIGTERM received — finishing current batch then shutting down")
    shutdown_requested = True

signal.signal(signal.SIGTERM, handle_sigterm)
signal.signal(signal.SIGINT, handle_sigterm)

# ---------------------------------------------------------------------------
# Business logic
# ---------------------------------------------------------------------------

def process_item(payload: dict) -> bool:
    """
    Simulate processing an item. In a real system this would call an
    external API, run a transform, or execute ML inference.
    Returns True on success, False on failure.
    """
    item_id  = payload["item_id"]
    priority = int(payload.get("priority", 1))

    logger.info("Processing item %s (priority=%d, worker=%s)", item_id, priority, WORKER_ID)

    # Simulate work duration based on priority (high priority = less wait)
    work_seconds = max(0.5, 3.0 - (priority * 0.2))
    time.sleep(work_seconds)

    # Simulate a 5% failure rate for realistic error budget tracking
    if hash(item_id) % 20 == 0:
        logger.warning("Simulated failure for item %s", item_id)
        return False

    return True


def update_item_status(item_id: str, new_status: str, processed_at: str):
    """Update item status in DynamoDB after processing."""
    try:
        # Fetch the item to get its sort key (created_at)
        response = table.scan(
            FilterExpression="id = :id",
            ExpressionAttributeValues={":id": item_id},
            Limit=1,
        )
        items = response.get("Items", [])
        if not items:
            logger.warning("Item %s not found in DynamoDB for status update", item_id)
            return

        item = items[0]
        table.update_item(
            Key={"id": item["id"], "created_at": item["created_at"]},
            UpdateExpression="SET #s = :s, processed_at = :p, processed_by = :w",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":s": new_status,
                ":p": processed_at,
                ":w": WORKER_ID,
            },
        )
        logger.info("Updated item %s status → %s", item_id, new_status)
    except ClientError as e:
        logger.error("DynamoDB update failed for item %s: %s", item_id, str(e))


def emit_metrics(processed: int, failed: int, queue_depth: int):
    """Push custom metrics to CloudWatch for dashboards and KEDA."""
    try:
        timestamp = datetime.now(timezone.utc)
        dimensions = [
            {"Name": "Environment", "Value": ENVIRONMENT},
            {"Name": "WorkerId",    "Value": WORKER_ID},
        ]
        cw.put_metric_data(
            Namespace="EKSGitOpsPlatform/WorkerService",
            MetricData=[
                {
                    "MetricName": "MessagesProcessed",
                    "Dimensions": dimensions,
                    "Value": processed,
                    "Unit": "Count",
                    "Timestamp": timestamp,
                },
                {
                    "MetricName": "MessagesFailed",
                    "Dimensions": dimensions,
                    "Value": failed,
                    "Unit": "Count",
                    "Timestamp": timestamp,
                },
                {
                    "MetricName": "QueueDepth",
                    "Dimensions": [{"Name": "Environment", "Value": ENVIRONMENT}],
                    "Value": queue_depth,
                    "Unit": "Count",
                    "Timestamp": timestamp,
                },
            ],
        )
    except ClientError as e:
        logger.warning("Failed to emit CloudWatch metrics: %s", str(e))


def get_queue_depth() -> int:
    """Return approximate number of messages in the SQS queue."""
    try:
        resp = sqs.get_queue_attributes(
            QueueUrl=SQS_QUEUE_URL,
            AttributeNames=["ApproximateNumberOfMessages"],
        )
        return int(resp["Attributes"].get("ApproximateNumberOfMessages", 0))
    except ClientError:
        return -1


def process_batch(messages: list) -> tuple[int, int]:
    """Process a batch of SQS messages. Returns (processed_count, failed_count)."""
    processed = 0
    failed    = 0

    for message in messages:
        receipt_handle = message["ReceiptHandle"]
        try:
            payload      = json.loads(message["Body"])
            item_id      = payload["item_id"]
            processed_at = datetime.now(timezone.utc).isoformat()

            # Mark as processing
            update_item_status(item_id, "processing", processed_at)

            success = process_item(payload)
            final_status = "completed" if success else "failed"
            update_item_status(item_id, final_status, datetime.now(timezone.utc).isoformat())

            if success:
                # Delete from queue only on success — failures stay for DLQ retry
                sqs.delete_message(QueueUrl=SQS_QUEUE_URL, ReceiptHandle=receipt_handle)
                processed += 1
            else:
                failed += 1

        except json.JSONDecodeError as e:
            logger.error("Invalid message body (not JSON): %s", str(e))
            sqs.delete_message(QueueUrl=SQS_QUEUE_URL, ReceiptHandle=receipt_handle)
            failed += 1
        except Exception as e:
            logger.error("Unexpected error processing message: %s", str(e))
            failed += 1

    return processed, failed


# ---------------------------------------------------------------------------
# Main poll loop
# ---------------------------------------------------------------------------

def main():
    logger.info("Worker service starting — queue=%s table=%s", SQS_QUEUE_URL, DYNAMODB_TABLE)

    total_processed = 0
    total_failed    = 0

    while not shutdown_requested:
        try:
            # Long-poll SQS — blocks for up to POLL_WAIT_SECONDS if queue is empty
            response = sqs.receive_message(
                QueueUrl            = SQS_QUEUE_URL,
                MaxNumberOfMessages = MAX_MESSAGES,
                WaitTimeSeconds     = POLL_WAIT_SECONDS,
                AttributeNames      = ["All"],
                MessageAttributeNames = ["All"],
            )

            messages = response.get("Messages", [])
            if not messages:
                logger.debug("No messages in queue — long polling again")
                continue

            logger.info("Received %d messages", len(messages))
            processed, failed = process_batch(messages)
            total_processed += processed
            total_failed    += failed

            queue_depth = get_queue_depth()
            emit_metrics(processed, failed, queue_depth)

            logger.info(
                "Batch complete: processed=%d failed=%d queue_depth=%d total_processed=%d",
                processed, failed, queue_depth, total_processed,
            )

        except ClientError as e:
            error_code = e.response["Error"]["Code"]
            logger.error("SQS receive error (%s): %s", error_code, str(e))
            time.sleep(5)  # Back-off before retry
        except Exception as e:
            logger.error("Unexpected poll loop error: %s", str(e))
            time.sleep(5)

    logger.info(
        "Shutdown complete — total processed=%d total failed=%d",
        total_processed, total_failed,
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
