# Arquitetura do Servidor Web InfraLab

Fluxo de Requisição:
CLIENTE -> NGINX (Porta 80) -> FASTAPI/UVICORN (Porta 8000) -> POSTGRESQL (Porta 5432)

1. Nginx (Proxy Reverso): Ponto de entrada HTTP na porta 80. Repassa tráfego mantendo os cabeçalhos HTTP necessários (Host, X-Real-IP, X-Forwarded-For).
2. FastAPI & Uvicorn: Lógica de negócio, validação via Pydantic e OpenAPI.
3. SQLAlchemy & Banco de Dados: Comunicação relacional com o PostgreSQL do Luiz.
4. Systemd: Gerenciamento do serviço .
