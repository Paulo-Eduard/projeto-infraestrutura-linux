# Mapeamento de Portas de Rede — Servidor Web InfraLab

| Porta | Protocolo | Serviço | Exposição Externa | Descrição |
|---|---|---|---|---|
|  | TCP | Nginx | **SIM** | Entrada padrão HTTP para os clientes da rede |
|  | TCP | Nginx | **SIM** | Entrada HTTPS segura (suporte preparado) |
|  | TCP | Uvicorn/FastAPI | **NÃO** () | Backend da aplicação processando via Proxy |
|  | TCP | PostgreSQL | **NÃO** (Rede local) | Conexão de banco fornecida pelo componente do Luiz |
