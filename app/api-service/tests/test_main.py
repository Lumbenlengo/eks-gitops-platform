"""
test_main.py — app/api-service/tests/test_main.py

Full test suite. AWS is mocked in conftest.py before this file is imported.
"""
import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


# ---------------------------------------------------------------------------
# /health
# ---------------------------------------------------------------------------

def test_health_returns_200():
    response = client.get("/health")
    assert response.status_code == 200


def test_health_response_fields():
    data = client.get("/health").json()
    assert data["status"] == "healthy"
    assert "hostname" in data
    assert "availability_zone" in data
    assert "environment" in data
    assert "version" in data
    assert "timestamp" in data


def test_health_environment_is_test():
    assert client.get("/health").json()["environment"] == "test"


# ---------------------------------------------------------------------------
# GET /items
# ---------------------------------------------------------------------------

def test_list_items_empty(mock_table):
    mock_table.scan.return_value = {"Items": []}
    response = client.get("/items")
    assert response.status_code == 200
    assert response.json() == []


def test_list_items_returns_items(mock_table):
    mock_table.scan.return_value = {"Items": [
        {
            "id": "abc-123",
            "name": "Test Item",
            "description": "A test",
            "priority": 3,
            "status": "pending",
            "created_at": "2024-01-01T00:00:00+00:00",
        }
    ]}
    items = client.get("/items").json()
    assert len(items) == 1
    assert items[0]["id"] == "abc-123"
    assert items[0]["priority"] == 3


def test_list_items_no_description(mock_table):
    mock_table.scan.return_value = {"Items": [
        {
            "id": "abc-456",
            "name": "No Desc",
            "priority": 1,
            "status": "pending",
            "created_at": "2024-01-01T00:00:00+00:00",
        }
    ]}
    assert client.get("/items").json()[0]["description"] is None


def test_list_items_with_status_filter(mock_table):
    mock_table.query.return_value = {"Items": []}
    response = client.get("/items?status_filter=pending")
    assert response.status_code == 200


def test_list_items_with_limit():
    response = client.get("/items?limit=5")
    assert response.status_code == 200


def test_list_items_dynamo_error(mock_table):
    mock_table.scan.side_effect = Exception("DynamoDB down")
    assert client.get("/items").status_code == 500
    mock_table.scan.side_effect = None


# ---------------------------------------------------------------------------
# GET /items/{item_id}
# ---------------------------------------------------------------------------

def test_get_item_found(mock_table):
    mock_table.scan.return_value = {"Items": [
        {
            "id": "item-1",
            "name": "Found Item",
            "description": "desc",
            "priority": 5,
            "status": "pending",
            "created_at": "2024-01-01T00:00:00+00:00",
        }
    ]}
    response = client.get("/items/item-1")
    assert response.status_code == 200
    assert response.json()["name"] == "Found Item"


def test_get_item_not_found(mock_table):
    mock_table.scan.return_value = {"Items": []}
    assert client.get("/items/nonexistent").status_code == 404


def test_get_item_404_message(mock_table):
    mock_table.scan.return_value = {"Items": []}
    assert "not found" in client.get("/items/x").json()["detail"].lower()


def test_get_item_dynamo_error(mock_table):
    mock_table.scan.side_effect = Exception("boom")
    assert client.get("/items/any-id").status_code == 500
    mock_table.scan.side_effect = None


# ---------------------------------------------------------------------------
# POST /items
# ---------------------------------------------------------------------------

def test_create_item_returns_201():
    assert client.post("/items", json={"name": "Test Item", "priority": 5}).status_code == 201


def test_create_item_fields():
    data = client.post("/items", json={"name": "Test Item", "priority": 3}).json()
    assert data["name"] == "Test Item"
    assert data["priority"] == 3
    assert data["status"] == "pending"
    assert "id" in data
    assert "created_at" in data


def test_create_item_with_description():
    data = client.post("/items", json={"name": "With desc", "priority": 7, "description": "hello"}).json()
    assert data["description"] == "hello"


def test_create_item_default_priority():
    data = client.post("/items", json={"name": "Defaults"}).json()
    assert data["priority"] == 1


def test_create_item_priority_boundaries():
    assert client.post("/items", json={"name": "min", "priority": 1}).status_code == 201
    assert client.post("/items", json={"name": "max", "priority": 10}).status_code == 201


def test_create_item_priority_too_high():
    assert client.post("/items", json={"name": "Bad", "priority": 11}).status_code == 422


def test_create_item_priority_zero():
    assert client.post("/items", json={"name": "Bad", "priority": 0}).status_code == 422


def test_create_item_empty_name():
    assert client.post("/items", json={"name": ""}).status_code == 422


def test_create_item_missing_name():
    assert client.post("/items", json={"priority": 3}).status_code == 422


def test_create_item_dynamo_failure(mock_table):
    mock_table.put_item.side_effect = Exception("DynamoDB error")
    assert client.post("/items", json={"name": "Will Fail"}).status_code == 500
    mock_table.put_item.side_effect = None


def test_create_item_sqs_failure_still_201(mock_sqs):
    """SQS failure is non-fatal — item must still be created."""
    mock_sqs.send_message.side_effect = Exception("SQS down")
    assert client.post("/items", json={"name": "SQS Fail"}).status_code == 201
    mock_sqs.send_message.side_effect = None


# ---------------------------------------------------------------------------
# DELETE /items/{item_id}
# ---------------------------------------------------------------------------

def test_delete_item_success(mock_table):
    mock_table.scan.return_value = {"Items": [
        {
            "id": "del-1",
            "name": "To Delete",
            "priority": 1,
            "status": "pending",
            "created_at": "2024-01-01T00:00:00+00:00",
        }
    ]}
    assert client.delete("/items/del-1").status_code == 204


def test_delete_item_not_found(mock_table):
    mock_table.scan.return_value = {"Items": []}
    assert client.delete("/items/ghost").status_code == 404


def test_delete_item_dynamo_error(mock_table):
    mock_table.scan.side_effect = Exception("error")
    assert client.delete("/items/any").status_code == 500
    mock_table.scan.side_effect = None


# ---------------------------------------------------------------------------
# GET /metrics
# ---------------------------------------------------------------------------

def test_metrics_returns_200():
    assert client.get("/metrics").status_code == 200


def test_metrics_prometheus_format():
    response = client.get("/metrics")
    assert "text/plain" in response.headers.get("content-type", "") 