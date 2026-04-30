"""
test_main.py — app/api-service/tests/test_main.py

Tests for the API service. All AWS calls are mocked via conftest.py.
Coverage target: >80% of main.py
"""
import pytest
from fastapi.testclient import TestClient


# ---------------------------------------------------------------------------
# Import app AFTER conftest has set env vars and patched boto3
# ---------------------------------------------------------------------------
from main import app

client = TestClient(app)


# ---------------------------------------------------------------------------
# /health
# ---------------------------------------------------------------------------

def test_health_returns_200():
    response = client.get("/health")
    assert response.status_code == 200


def test_health_returns_correct_fields():
    data = client.get("/health").json()
    assert data["status"]      == "healthy"
    assert "hostname"          in data
    assert "availability_zone" in data
    assert "environment"       in data
    assert "version"           in data
    assert "timestamp"         in data


def test_health_environment_is_test():
    data = client.get("/health").json()
    assert data["environment"] == "test"


# ---------------------------------------------------------------------------
# GET /items
# ---------------------------------------------------------------------------

def test_list_items_returns_200():
    response = client.get("/items")
    assert response.status_code == 200


def test_list_items_returns_list():
    data = client.get("/items").json()
    assert isinstance(data, list)


def test_list_items_with_status_filter():
    response = client.get("/items?status_filter=pending")
    assert response.status_code == 200


def test_list_items_with_limit():
    response = client.get("/items?limit=5")
    assert response.status_code == 200


# ---------------------------------------------------------------------------
# GET /items/{item_id}
# ---------------------------------------------------------------------------

def test_get_item_not_found_returns_404():
    response = client.get("/items/nonexistent-id")
    assert response.status_code == 404


def test_get_item_404_message():
    response = client.get("/items/nonexistent-id")
    assert "not found" in response.json()["detail"].lower()


# ---------------------------------------------------------------------------
# POST /items
# ---------------------------------------------------------------------------

def test_create_item_returns_201():
    payload = {"name": "Test Item", "priority": 5}
    response = client.post("/items", json=payload)
    assert response.status_code == 201


def test_create_item_returns_correct_fields():
    payload = {"name": "Test Item", "priority": 3}
    data = client.post("/items", json=payload).json()
    assert "id"         in data
    assert "name"       in data
    assert "status"     in data
    assert "created_at" in data
    assert data["name"]     == "Test Item"
    assert data["priority"] == 3
    assert data["status"]   == "pending"


def test_create_item_with_description():
    payload = {"name": "Item with desc", "priority": 7, "description": "Test description"}
    data = client.post("/items", json=payload).json()
    assert data["description"] == "Test description"


def test_create_item_priority_range_valid():
    for priority in [1, 5, 10]:
        response = client.post("/items", json={"name": f"Item p{priority}", "priority": priority})
        assert response.status_code == 201


def test_create_item_priority_out_of_range():
    response = client.post("/items", json={"name": "Bad Item", "priority": 11})
    assert response.status_code == 422


def test_create_item_priority_zero_invalid():
    response = client.post("/items", json={"name": "Bad Item", "priority": 0})
    assert response.status_code == 422


def test_create_item_empty_name_invalid():
    response = client.post("/items", json={"name": "", "priority": 5})
    assert response.status_code == 422


def test_create_item_missing_name_invalid():
    response = client.post("/items", json={"priority": 5})
    assert response.status_code == 422


def test_create_item_default_priority():
    response = client.post("/items", json={"name": "Default priority item"})
    assert response.status_code == 201
    assert response.json()["priority"] == 1


# ---------------------------------------------------------------------------
# DELETE /items/{item_id}
# ---------------------------------------------------------------------------

def test_delete_item_not_found_returns_404():
    response = client.delete("/items/nonexistent-id")
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# GET /metrics
# ---------------------------------------------------------------------------

def test_metrics_endpoint_exists():
    response = client.get("/metrics")
    assert response.status_code == 200


def test_metrics_returns_prometheus_format():
    response = client.get("/metrics")
    # Prometheus format uses plain text with metric lines
    assert "text/plain" in response.headers.get("content-type", "")
