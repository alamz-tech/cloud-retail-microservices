import pytest
from unittest.mock import MagicMock
from fastapi.testclient import TestClient

from app.main import app
from app.database import get_db

client = TestClient(app)

def test_read_root():
    """Verify that the root endpoint returns service metadata and online status."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["service"] == "Cloud Retail Backend Microservice"
    assert data["status"] == "online"
    assert "health" in data["endpoints"]
    assert "products" in data["endpoints"]

def test_health_check_healthy():
    """Verify health check returns healthy status when database is reachable."""
    mock_db = MagicMock()
    mock_db.execute.return_value = True

    # Override get_db dependency
    app.dependency_overrides[get_db] = lambda: mock_db

    try:
        response = client.get("/api/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert data["database"] == "connected"
    finally:
        app.dependency_overrides.clear()

def test_health_check_unhealthy():
    """Verify health check returns 503 when database query fails."""
    mock_db = MagicMock()
    mock_db.execute.side_effect = Exception("Database connection failed")

    app.dependency_overrides[get_db] = lambda: mock_db

    try:
        response = client.get("/api/health")
        assert response.status_code == 503
        data = response.json()
        assert data["detail"]["status"] == "unhealthy"
        assert data["detail"]["database"] == "disconnected"
    finally:
        app.dependency_overrides.clear()

def test_get_products():
    """Verify products endpoint returns formatted product list."""
    mock_product = MagicMock()
    mock_product.to_dict.return_value = {
        "id": 1,
        "name": "Test Mechanical Keyboard",
        "description": "High performance keyboard",
        "price": 99.99,
        "stock": 10,
    }

    mock_db = MagicMock()
    mock_query = MagicMock()
    mock_order = MagicMock()
    mock_order.all.return_value = [mock_product]
    mock_query.order_by.return_value = mock_order
    mock_db.query.return_value = mock_query

    app.dependency_overrides[get_db] = lambda: mock_db

    try:
        response = client.get("/api/products")
        assert response.status_code == 200
        data = response.json()
        assert len(data) == 1
        assert data[0]["name"] == "Test Mechanical Keyboard"
        assert data[0]["price"] == 99.99
    finally:
        app.dependency_overrides.clear()
