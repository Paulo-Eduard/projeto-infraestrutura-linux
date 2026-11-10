# Guia de Instalação e Implantação

Requisitos: Ubuntu Server LTS ou Debian, Python 3.10+, Nginx.

Passos:
1. Clonar repositório
2. Executar: bash scripts/install.sh
   (implanta em /opt/infralab/01-Paulo-Servidor-Web, cria o usuário `infralab`,
   o venv, a configuração do Nginx e a unit systemd)
3. Configurar o banco: editar /opt/infralab/01-Paulo-Servidor-Web/fastapi/.env
   e definir DATABASE_URL (ver configuracoes/variaveis-ambiente.md)
4. Iniciar: bash scripts/start.sh
5. Verificar: bash scripts/status.sh e bash scripts/healthcheck.sh

Diagnóstico: se /health/ready retornar 503, ou se o log mostrar SQLite em vez de PostgreSQL,
confira `sudo journalctl -u infralab-api -n 50` (linha "Banco de dados em uso").
