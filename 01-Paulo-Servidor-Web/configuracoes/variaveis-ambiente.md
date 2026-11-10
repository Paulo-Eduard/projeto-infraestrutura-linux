# Referência das Variáveis de Ambiente (.env)

O arquivo fica em `fastapi/.env` (modelo: `fastapi/.env.example`).

**Como é carregado**

- Em produção, pelo systemd: a unit `infralab-api.service` tem
  `EnvironmentFile=/opt/infralab/01-Paulo-Servidor-Web/fastapi/.env`.
- Em execução manual/dev, o próprio app lê `fastapi/.env` via `python-dotenv`.
- Variáveis já definidas no ambiente do processo têm precedência sobre o `.env`.
- Após editar o `.env`: `sudo systemctl restart infralab-api`.

**Variáveis**

- `APP_NAME`: Nome identificador da API (Padrão: `InfraLab Web API`)
- `APP_VERSION`: Versão da aplicação (Padrão: `1.0.0`)
- `ENVIRONMENT`: Ambiente de execução (`development` / `production`). Em `production`, a ausência de `DATABASE_URL` impede a API de iniciar.
- `DEBUG`: Habilita detalhamento em logs de exceção (`True` / `False`; Padrão: `False`)
- `HOST`: Endereço de escuta do Uvicorn (`127.0.0.1`)
- `PORT`: Porta interna do Uvicorn (`8000`)
- `DATABASE_URL`: String de conexão SQLAlchemy do PostgreSQL
  (`postgresql+psycopg2://infralab_user:SENHA@192.168.30.10:5432/infralab_db`)
- `ALLOWED_ORIGINS`: Origens permitidas para requisições CORS (separadas por vírgula; `*` libera todas)

**Senha com caracteres especiais**

Caracteres como `@`, `#`, `!`, `:`, `/` e `%` na senha precisam ser codificados na URL
(ex.: `@` vira `%40`). Para gerar a senha já codificada:

```bash
python3 -c "import urllib.parse,getpass; print(urllib.parse.quote(getpass.getpass(), safe=''))"
```

Não use aspas na linha do `DATABASE_URL`.
