# Relatório de Testes Automatizados

Suíte de testes desenvolvida para validação completa da API FastAPI com SQLite em memória.

Execução:
PYTHONPATH=fastapi python3 fastapi/tests/run_tests.py

Cobertura:
1. Rota principal GET / (200 OK)
2. Rota de saúde GET /health (200 OK)
3. Rota de prontidão GET /health/ready (200 OK com banco conectado)
4. CRUD completo de Itens (POST 201, GET 200, PUT 200, DELETE 204, GET 404)
5. Validação de erros Pydantic (POST com preço negativo 422)
