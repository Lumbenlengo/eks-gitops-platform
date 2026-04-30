"""
conftest.py — app/api-service/tests/conftest.py

Sets all required environment variables BEFORE any import of main.py.
This is critical: FastAPI/boto3 reads env vars at module load time,
so they must exist before `from main import app` runs.
"""
import os
import pytest
from unittest.mock import MagicMock, patch

# ---------------------------------------------------------------------------
# Environment variables — must be set before importing main
# ---------------------------------------------------------------------------
os.environ.setdefault("SQS_QUEUE_URL",  "https://sqs.us-east-1.amazonaws.com/123456789012/test-queue")
os.environ.setdefault("DYNAMODB_TABLE", "test-items")
os.environ.setdefault("AWS_REGION",     "us-east-1")
os.environ.setdefault("ENVIRONMENT",    "test")
os.environ.setdefault("SERVICE_VERSION","test-v1")

# ---------------------------------------------------------------------------
# Mock AWS clients — prevent real boto3 calls during tests
# boto3 is patched at the module level so main.py never touches real AWS
# ---------------------------------------------------------------------------
@pytest.fixture(autouse=True)
def mock_aws(monkeypatch):
    """Auto-applied fixture: replaces all boto3 AWS clients with mocks."""

    mock_table = MagicMock()
    mock_table.scan.return_value  = {"Items": []}
    mock_table.query.return_value = {"Items": []}
    mock_table.put_item.return_value = {}
    mock_table.update_item.return_value = {}

    mock_sqs = MagicMock()
    mock_sqs.send_message.return_value = {"MessageId": "mock-message-id"}

    mock_dynamodb = MagicMock()
    mock_dynamodb.Table.return_value = mock_table

    monkeypatch.setattr("boto3.client",   lambda service, **kwargs: mock_sqs if service == "sqs" else MagicMock())
    monkeypatch.setattr("boto3.resource", lambda service, **kwargs: mock_dynamodb)