# InfraLab — Servidor Web Linux
## Responsável: Paulo
## Área: Backend, Servidor Web, Systemd, DevOps e Infraestrutura

Este repositório contém a implementação completa do componente **Servidor Web** do projeto InfraLab.

---

## 🚀 Tecnologias Utilizadas

- **Sistema Operacional**: Ubuntu Server LTS / Debian
- **Servidor Web & Proxy Reverso**: Nginx (Porta 80)
- **Linguagem Principal**: Python 3.12+
- **Framework Backend**: FastAPI (Uvicorn na Porta 8000)
- **ORM & Banco de Dados**: SQLAlchemy (PostgreSQL / SQLite Dev)
- **Validação de Dados**: Pydantic v2
- **Gerenciador de Serviços**: Systemd (`infralab-api.service`)
- **Automação**: Linux Shell Script (`scripts/*.sh`)
- **Testes Automatizados**: Unittest / TestClient

---

## 📂 Estrutura de Diretórios

01-Paulo-Servidor-Web/
├── README.md
├── fastapi/
│   ├── requirements.txt
│   ├── .env.example
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py
│   │   ├── config.py
│   │   ├── database.py
│   │   ├── models/
│   │   ├── schemas/
│   │   └── routes/
│   └── tests/
│       └── run_tests.py
├── nginx/
│   └── site.conf
├── scripts/
│   ├── install.sh
│   ├── start.sh
│   ├── stop.sh
│   ├── status.sh
│   ├── healthcheck.sh
│   └── backup-config.sh
├── systemd/
│   └── infralab-api.service
├── configuracoes/
│   ├── firewall-referencia.md
│   ├── portas.md
│   └── variaveis-ambiente.md
└── docs/
    ├── arquitetura.md
    ├── instalacao.md
    ├── integracao.md
    └── testes.md

---

## ⚙️ Instalação e Execução

### 1. Instalação Automática (Linux Ubuntu/Debian)
bash scripts/install.sh

### 2. Configuração do banco (.env)
Edite `/opt/infralab/01-Paulo-Servidor-Web/fastapi/.env` e defina:

    DATABASE_URL=postgresql+psycopg2://infralab_user:SENHA@192.168.30.10:5432/infralab_db

Senhas com `@`, `#` ou `!` devem ser codificadas na URL (ex.: `@` vira `%40`).
Detalhes em `configuracoes/variaveis-ambiente.md`.

### 3. Execução dos Testes Automatizados
PYTHONPATH=fastapi python3 fastapi/tests/run_tests.py

### 4. Gerenciamento de Serviços
bash scripts/start.sh
bash scripts/status.sh
bash scripts/healthcheck.sh
bash scripts/stop.sh

---

## 🔍 Rotas da API

- GET / : Informações gerais
- GET /health : Checagem de saúde
- GET /health/ready : Validação de prontidão com banco de dados
- GET /api/v1/items : Listagem paginada de itens
- GET /api/v1/items/{id} : Consulta por ID
- POST /api/v1/items : Cadastro de item
- PUT /api/v1/items/{id} : Atualização de item
- DELETE /api/v1/items/{id} : Remoção de item
