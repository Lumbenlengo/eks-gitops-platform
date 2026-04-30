"""
API Service — eks-gitops-platform
FastAPI application that:
  - Exposes GET /health  (returns pod hostname + AZ — proves Multi-AZ)
  - Exposes GET /items   (reads from DynamoDB)
  - Exposes POST /items  (writes to DynamoDB + publishes to SQS)
  - Exposes GET /metrics (Prometheus-compatible via prometheus_fastapi_instrumentator)

All AWS credentials come from IRSA (IAM Roles for Service Accounts).
"""

import json
import logging
import os
import socket
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from typing import Optional, List, Any

import boto3
from fastapi import FastAPI, HTTPException, Response, status
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Logging — JSON structured for CloudWatch Logs Insights
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "message": "%(message)s"}',
)
logger = logging.getLogger("api-service")

# ---------------------------------------------------------------------------
# Configuration from environment
# ---------------------------------------------------------------------------
AWS_REGION      = os.environ.get("AWS_REGION", "us-east-1")
SQS_QUEUE_URL   = os.environ["SQS_QUEUE_URL"]
DYNAMODB_TABLE  = os.environ["DYNAMODB_TABLE"]
ENVIRONMENT     = os.environ.get("ENVIRONMENT", "prod")
SERVICE_VERSION = os.environ.get("SERVICE_VERSION", "unknown")

# ---------------------------------------------------------------------------
# AWS Clients
# ---------------------------------------------------------------------------
sqs      = boto3.client("sqs",       region_name=AWS_REGION)
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table    = dynamodb.Table(DYNAMODB_TABLE)

# ---------------------------------------------------------------------------
# App Initialization
# ---------------------------------------------------------------------------
app = FastAPI(
    title="EKS GitOps API Service",
    description="Production-grade FastAPI service running on EKS with IRSA",
    version=SERVICE_VERSION,
    docs_url="/docs" if ENVIRONMENT != "prod" else None,
    redoc_url=None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# Prometheus metrics
Instrumentator().instrument(app).expose(app, endpoint="/metrics")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _to_int(value: Any, default: int = 1) -> int:
    """Convert a DynamoDB value (Decimal, str, int, None) to int safely."""
    if value is None:
        return default
    if isinstance(value, Decimal):
        return int(value)
    return int(value)


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------

class ItemCreate(BaseModel):
    name:        str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = Field(None, max_length=1000)
    priority:    int = Field(default=1, ge=1, le=10)

class ItemResponse(BaseModel):
    id:          str
    name:        str
    description: Optional[str]
    priority:    int
    status:      str
    created_at:  str

class HealthResponse(BaseModel):
    status:            str
    hostname:          str
    availability_zone: str
    environment:       str
    version:           str
    timestamp:         str

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/health", response_model=HealthResponse, tags=["ops"])
async def health() -> HealthResponse:
    """Health check endpoint proving Multi-AZ via env var or IMDSv2."""
    return HealthResponse(
        status="healthy",
        hostname=socket.gethostname(),
        availability_zone=os.environ.get("NODE_AZ", "unknown"),
        environment=ENVIRONMENT,
        version=SERVICE_VERSION,
        timestamp=datetime.now(timezone.utc).isoformat(),
    )

@app.get("/items", response_model=List[ItemResponse], tags=["items"])
async def list_items(status_filter: Optional[str] = None, limit: int = 20) -> List[ItemResponse]:
    """List items from DynamoDB."""
    try:
        if status_filter:
            response = table.query(
                IndexName="StatusIndex",
                KeyConditionExpression="status = :s",
                ExpressionAttributeValues={":s": status_filter},
                Limit=limit,
                ScanIndexForward=False,
            )
        else:
            response = table.scan(Limit=limit)

        items = response.get("Items", [])
        return [
            ItemResponse(
                id=str(item.get("id", "")),
                name=str(item.get("name", "")),
                description=str(item["description"]) if item.get("description") is not None else None,
                priority=_to_int(item.get("priority"), default=1),
                status=str(item.get("status", "")),
                created_at=str(item.get("created_at", "")),
            )
            for item in items
        ]
    except Exception as e:
        logger.error("Failed to list items: %s", str(e))
        raise HTTPException(status_code=500, detail="Failed to retrieve items")

@app.get("/items/{item_id}", response_model=ItemResponse, tags=["items"])
async def get_item(item_id: str) -> ItemResponse:
    """Get a single item."""
    try:
        response = table.scan(
            FilterExpression="id = :id",
            ExpressionAttributeValues={":id": item_id},
            Limit=1,
        )
        items = response.get("Items", [])
        if not items:
            raise HTTPException(status_code=404, detail=f"Item {item_id} not found")

        item = items[0]
        return ItemResponse(
            id=str(item.get("id", "")),
            name=str(item.get("name", "")),
            description=str(item["description"]) if item.get("description") is not None else None,
            priority=_to_int(item.get("priority"), default=1),
            status=str(item.get("status", "")),
            created_at=str(item.get("created_at", "")),
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to get item %s: %s", item_id, str(e))
        raise HTTPException(status_code=500, detail="Failed to retrieve item")

@app.post("/items", response_model=ItemResponse, status_code=status.HTTP_201_CREATED, tags=["items"])
async def create_item(item: ItemCreate) -> ItemResponse:
    """Create item and publish to SQS."""
    item_id    = str(uuid.uuid4())
    created_at = datetime.now(timezone.utc).isoformat()

    db_item = {
        "id":          item_id,
        "name":        item.name,
        "description": item.description,
        "priority":    item.priority,
        "status":      "pending",
        "created_at":  created_at,
    }

    try:
        table.put_item(Item=db_item)
        logger.info("Created item %s in DynamoDB", item_id)
    except Exception as e:
        logger.error("DynamoDB put_item failed: %s", str(e))
        raise HTTPException(status_code=500, detail="Failed to persist item")

    try:
        sqs.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps({
                "item_id":    item_id,
                "name":       item.name,
                "priority":   item.priority,
                "created_at": created_at,
                "action":     "process_item",
            }),
            MessageAttributes={
                "priority": {
                    "StringValue": str(item.priority),
                    "DataType": "Number",
                }
            },
        )
        logger.info("Published item %s to SQS", item_id)
    except Exception as e:
        logger.warning("SQS publish failed for item %s: %s", item_id, str(e))

    # db_item values are known Python types — access directly, no casting ambiguity
    return ItemResponse(
        id=item_id,
        name=item.name,
        description=item.description,
        priority=item.priority,
        status="pending",
        created_at=created_at,
    )

@app.delete("/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["items"])
async def delete_item(item_id: str) -> Response:
    """Soft-delete via status update."""
    try:
        response = table.scan(
            FilterExpression="id = :id",
            ExpressionAttributeValues={":id": item_id},
            Limit=1,
        )
        items = response.get("Items", [])
        if not items:
            raise HTTPException(status_code=404, detail=f"Item {item_id} not found")

        item = items[0]
        table.update_item(
            Key={"id": item["id"], "created_at": item["created_at"]},
            UpdateExpression="SET #s = :s",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":s": "deleted"},
        )
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to delete item %s: %s", item_id, str(e))
        raise HTTPException(status_code=500, detail="Failed to delete item")