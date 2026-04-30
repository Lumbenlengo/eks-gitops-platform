"""
API Service — eks-gitops-platform
FastAPI application with full type safety for EKS/GitOps demo.
"""

import json
import logging
import os
import socket
import uuid
from datetime import datetime, timezone
from typing import Optional, List

import boto3
import httpx
from fastapi import FastAPI, HTTPException, Response, status
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "message": "%(message)s"}',
)
logger = logging.getLogger("api-service")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
AWS_REGION       = os.environ.get("AWS_REGION", "us-east-1")
SQS_QUEUE_URL    = os.environ["SQS_QUEUE_URL"]
DYNAMODB_TABLE   = os.environ["DYNAMODB_TABLE"]
ENVIRONMENT      = os.environ.get("ENVIRONMENT", "prod")
SERVICE_VERSION   = os.environ.get("SERVICE_VERSION", "unknown")

sqs      = boto3.client("sqs",      region_name=AWS_REGION)
dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table    = dynamodb.Table(DYNAMODB_TABLE)

# ---------------------------------------------------------------------------
# App Init
# ---------------------------------------------------------------------------
app = FastAPI(
    title="EKS GitOps API Service",
    version=SERVICE_VERSION,
    docs_url="/docs" if ENVIRONMENT != "prod" else None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

Instrumentator().instrument(app).expose(app, endpoint="/metrics")

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
async def health():
    return {
        "status":            "healthy",
        "hostname":          socket.gethostname(),
        "availability_zone": os.environ.get("NODE_AZ", "unknown"),
        "environment":       ENVIRONMENT,
        "version":           SERVICE_VERSION,
        "timestamp":         datetime.now(timezone.utc).isoformat(),
    }

@app.get("/items", response_model=List[ItemResponse], tags=["items"])
async def list_items(status_filter: Optional[str] = None, limit: int = 20):
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
        # Correctly looping through the items list
        return [
            ItemResponse(
                id=str(item["id"]),
                name=str(item["name"]),
                description=item.get("description"),
                priority=int(item.get("priority", 1)),
                status=str(item["status"]),
                created_at=str(item["created_at"]),
            )
            for item in items
        ]
    except Exception as e:
        logger.error("Failed to list items: %s", str(e))
        raise HTTPException(status_code=500, detail="Failed to retrieve items")

@app.get("/items/{item_id}", response_model=ItemResponse, tags=["items"])
async def get_item(item_id: str):
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
            id=str(item["id"]),
            name=str(item["name"]),
            description=item.get("description"),
            priority=int(item.get("priority", 1)),
            status=str(item["status"]),
            created_at=str(item["created_at"]),
        )
    except Exception as e:
        logger.error("Failed to get item: %s", str(e))
        raise HTTPException(status_code=500, detail="Error fetching item")

@app.post("/items", response_model=ItemResponse, status_code=status.HTTP_201_CREATED, tags=["items"])
async def create_item(item: ItemCreate):
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
        sqs.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps({"item_id": item_id, "action": "process_item"}),
        )
        return ItemResponse(
            id=str(db_item["id"]),
            name=str(db_item["name"]),
            description=db_item.get("description"),
            priority=int(db_item.get("priority", 1)),
            status=str(db_item["status"]),
            created_at=str(db_item["created_at"])
        )
    except Exception as e:
        logger.error("Create failed: %s", str(e))
        raise HTTPException(status_code=500, detail="Failed to create item")

@app.delete("/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["items"])
async def delete_item(item_id: str):
    # Simplified delete for demo
    return Response(status_code=status.HTTP_204_NO_CONTENT)