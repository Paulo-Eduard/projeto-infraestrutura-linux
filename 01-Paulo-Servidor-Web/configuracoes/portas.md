# Mapeamento de Portas de Rede — Servidor Web InfraLab

| Porta | Protocolo | Serviço | Exposição Externa | Descrição |
|---|---|---|---|---|
| 80 | TCP | Nginx | **SIM** | Entrada padrão HTTP para os clientes da rede |
| 443 | TCP | Nginx | **SIM** | Entrada HTTPS segura (suporte preparado) |
| 8000 | TCP | Uvicorn/FastAPI | **NÃO** (127.0.0.1) | Backend da aplicação processando via Proxy |
| 5432 | TCP | PostgreSQL | **NÃO** (Rede local) | Conexão de banco fornecida pelo componente do Luiz (192.168.30.10) |
