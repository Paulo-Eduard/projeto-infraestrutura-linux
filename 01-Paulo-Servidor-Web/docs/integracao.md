# Contrato de Integração da Equipe InfraLab

1. Integração com Luiz (PostgreSQL):
- Host: localhost (ou IP da VM)
- Porta: 5432
- Banco: infralab_db
- Usuário: infralab_user
- Variável: DATABASE_URL

2. Integração com Ysaac (Redes & Firewall):
- Porta Exposta: 80 (HTTP)
- Porta Interna: 8000 (FastAPI / Uvicorn na 127.0.0.1)

3. Integração com Yahonan (Testes & QA):
- Endpoint Prontidão: GET /health/ready
- Testes: python3 fastapi/tests/run_tests.py

4. Integração com Rafael (Samba):
- Backend opera independentemente de compartilhamentos de arquivos.
