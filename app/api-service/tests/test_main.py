import os
import sys

# Ensure the app directory is in the path so we can import main
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_health_check():
    """Simple test to trigger code coverage"""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"
