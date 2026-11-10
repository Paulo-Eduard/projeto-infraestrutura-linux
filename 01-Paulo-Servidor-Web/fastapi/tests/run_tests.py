import unittest
import sys
import os

# Adiciona o diretório fastapi ao sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Isola os testes: sempre SQLite em memória, ignorando DATABASE_URL/.env reais.
# Deve ser definido ANTES de importar app.*
os.environ['DATABASE_URL'] = 'sqlite:///:memory:'

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.database import Base, get_db
from app.main import app

engine = create_engine(
    'sqlite:///:memory:',
    connect_args={'check_same_thread': False},
    poolclass=StaticPool,
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def override_get_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

app.dependency_overrides[get_db] = override_get_db

class TestFastAPIApp(unittest.TestCase):
    def setUp(self):
        Base.metadata.create_all(bind=engine)
        self.client = TestClient(app)

    def tearDown(self):
        Base.metadata.drop_all(bind=engine)

    def test_root_endpoint(self):
        response = self.client.get('/')
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['status'], 'online')
        self.assertIn('name', data)
        self.assertIn('version', data)

    def test_health_check(self):
        response = self.client.get('/health')
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['status'], 'healthy')

    def test_readiness_check(self):
        response = self.client.get('/health/ready')
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['status'], 'ready')
        self.assertEqual(data['database'], 'connected')

    def test_items_crud_lifecycle(self):
        # 1. Post (Create)
        create_resp = self.client.post('/api/v1/items', json={
            'title': 'Servidor Web InfraLab',
            'description': 'Nginx + FastAPI',
            'price': 1500.0,
            'is_active': True
        })
        self.assertEqual(create_resp.status_code, 201)
        item_id = create_resp.json()['id']

        # 2. Get All (List)
        list_resp = self.client.get('/api/v1/items')
        self.assertEqual(list_resp.status_code, 200)
        self.assertEqual(list_resp.json()['total'], 1)

        # 3. Get Single (Read)
        get_resp = self.client.get(f'/api/v1/items/{item_id}')
        self.assertEqual(get_resp.status_code, 200)
        self.assertEqual(get_resp.json()['title'], 'Servidor Web InfraLab')

        # 4. Put (Update)
        update_resp = self.client.put(f'/api/v1/items/{item_id}', json={'price': 1800.0})
        self.assertEqual(update_resp.status_code, 200)
        self.assertEqual(update_resp.json()['price'], 1800.0)

        # 5. Delete (Remove)
        del_resp = self.client.delete(f'/api/v1/items/{item_id}')
        self.assertEqual(del_resp.status_code, 204)

        # 6. Verify 404
        get_del = self.client.get(f'/api/v1/items/{item_id}')
        self.assertEqual(get_del.status_code, 404)

    def test_validation_error(self):
        response = self.client.post('/api/v1/items', json={'title': 'Invalido', 'price': -10.0})
        self.assertEqual(response.status_code, 422)

if __name__ == '__main__':
    unittest.main()
