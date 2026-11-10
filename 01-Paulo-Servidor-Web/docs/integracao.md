# Contrato de Integração da Equipe InfraLab

1. Integração com Luiz (PostgreSQL):
- Host: 192.168.30.10 (IP da VM do banco)
- Porta: 5432
- Banco: infralab_db
- Usuário: infralab_user
- Variável: DATABASE_URL (no fastapi/.env)
- Formato: postgresql+psycopg2://infralab_user:SENHA@192.168.30.10:5432/infralab_db
- Senha com @ # ! deve ser codificada na URL (ex.: @ vira %40)

2. Integração com Ysaac (Redes & Firewall):
- Porta Exposta: 80 (HTTP)
- Porta Interna: 8000 (FastAPI / Uvicorn na 127.0.0.1)

3. Integração com Yahonan (Testes & QA):
- Endpoint Prontidão: GET /health/ready
- Testes: python3 fastapi/tests/run_tests.py

4. Integração com Rafael (Samba):
- Backend opera independentemente de compartilhamentos de arquivos.
