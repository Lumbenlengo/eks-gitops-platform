"""
conftest.py — app/api-service/tests/conftest.py

Order of operations (critical):
  1. sys.path — so `from main import app` can find main.py
  2. os.environ — so main.py module-level code doesn't crash on missing vars
  3. boto3 patches started — so main.py never calls real AWS when imported
  4. main.py is imported (happens in test_main.py after this file runs)
"""
import os
import sys
from unittest.mock import MagicMock, patch

# ---------------------------------------------------------------------------
# 1. Fix sys.path — main.py lives one directory above this file
# ---------------------------------------------------------------------------
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

# ---------------------------------------------------------------------------
# 2. Environment variables — must exist before main.py is imported
# ---------------------------------------------------------------------------
os.environ.setdefault("SQS_QUEUE_URL",   "https://sqs.us-east-1.amazonaws.com/123456789012/test-queue")
os.environ.setdefault("DYNAMODB_TABLE",  "test-items")
os.environ.setdefault("AWS_REGION",      "us-east-1")
os.environ.setdefault("ENVIRONMENT",     "test")
os.environ.setdefault("SERVICE_VERSION", "test-v1")

# ---------------------------------------------------------------------------
# 3. Mock AWS at module level — patches must be started BEFORE main.py loads
#    because main.py calls boto3.client() and boto3.resource() at import time
# ---------------------------------------------------------------------------
_mock_sqs = MagicMock()
_mock_sqs.send_message.return_value = {"MessageId": "mock-message-id"}

_mock_table = MagicMock()
_mock_table.scan.return_value        = {"Items": []}
_mock_table.query.return_value       = {"Items": []}
_mock_table.put_item.return_value    = {}
_mock_table.update_item.return_value = {}

_mock_dynamodb = MagicMock()
_mock_dynamodb.Table.return_value = _mock_table

_client_patch   = patch("boto3.client",   side_effect=lambda svc, **kw: _mock_sqs if svc == "sqs" else MagicMock())
_resource_patch = patch("boto3.resource", return_value=_mock_dynamodb)

_client_patch.start()
_resource_patch.start()

# ---------------------------------------------------------------------------
# 4. Per-test reset — prevents state leaking between tests
# ---------------------------------------------------------------------------
import pytest  # noqa: E402


@pytest.fixture(autouse=True)
def reset_mocks():
    _mock_table.scan.reset_mock()
    _mock_table.scan.return_value        = {"Items": []}
    _mock_table.query.reset_mock()
    _mock_table.query.return_value       = {"Items": []}
    _mock_table.put_item.reset_mock()
    _mock_table.put_item.return_value    = {}
    _mock_table.update_item.reset_mock()
    _mock_table.update_item.return_value = {}
    _mock_sqs.send_message.reset_mock()
    _mock_sqs.send_message.return_value  = {"MessageId": "mock-message-id"}
    yield


@pytest.fixture
def mock_table():
    return _mock_table


@pytest.fixture
def mock_sqs():
    return _mock_sqs