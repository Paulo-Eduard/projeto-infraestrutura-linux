def test_create_item(client):
    payload = {
        "title": "Servidor Web Ubuntu",
        "description": "Servidor Nginx e FastAPI",
        "price": 1500.0,
        "is_active": True
    }
    response = client.post("/api/v1/items", json=payload)
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == payload["title"]
    assert data["price"] == payload["price"]
    assert "id" in data

def test_list_items(client):
    # Criar item primeiro
    client.post("/api/v1/items", json={"title": "Item A", "price": 100.0})
    client.post("/api/v1/items", json={"title": "Item B", "price": 200.0})

    response = client.get("/api/v1/items")
    assert response.status_code == 200
    data = response.json()
    assert data["total"] == 2
    assert len(data["items"]) == 2

def test_get_item_by_id(client):
    create_resp = client.post("/api/v1/items", json={"title": "Item Teste", "price": 50.0})
    item_id = create_resp.json()["id"]

    response = client.get(f"/api/v1/items/{item_id}")
    assert response.status_code == 200
    assert response.json()["title"] == "Item Teste"

def test_get_item_not_found(client):
    response = client.get("/api/v1/items/9999")
    assert response.status_code == 404

def test_update_item(client):
    create_resp = client.post("/api/v1/items", json={"title": "Antigo", "price": 10.0})
    item_id = create_resp.json()["id"]

    update_payload = {"title": "Novo Titulo", "price": 25.5}
    response = client.put(f"/api/v1/items/{item_id}", json=update_payload)
    assert response.status_code == 200
    assert response.json()["title"] == "Novo Titulo"
    assert response.json()["price"] == 25.5

def test_delete_item(client):
    create_resp = client.post("/api/v1/items", json={"title": "Deletar", "price": 30.0})
    item_id = create_resp.json()["id"]

    del_resp = client.delete(f"/api/v1/items/{item_id}")
    assert del_resp.status_code == 204

    get_resp = client.get(f"/api/v1/items/{item_id}")
    assert get_resp.status_code == 404

def test_create_item_invalid_data(client):
    # Preço inválido (negativo)
    response = client.post("/api/v1/items", json={"title": "Inválido", "price": -10.0})
    assert response.status_code == 422
