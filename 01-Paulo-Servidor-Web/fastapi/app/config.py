"""Configuracao da aplicacao.

Ordem de precedencia (da maior para a menor):
  1. Variaveis de ambiente reais do processo (ex.: systemd EnvironmentFile=)
  2. Arquivo fastapi/.env (lido via python-dotenv; fallback para dev/execucao manual)
  3. Valores padrao definidos abaixo
"""
import logging
import os
from pathlib import Path

from dotenv import load_dotenv
from pydantic import BaseModel

logger = logging.getLogger(__name__)

# .../fastapi  (independe do diretorio de onde o processo foi iniciado)
BASE_DIR = Path(__file__).resolve().parent.parent
ENV_FILE = BASE_DIR / '.env'


def _load_env_file() -> None:
    """Carrega fastapi/.env sem sobrescrever variaveis ja presentes no ambiente."""
    try:
        if ENV_FILE.is_file():
            load_dotenv(ENV_FILE, override=False)
    except OSError as exc:  # ex.: sem permissao de leitura no .env
        logger.warning('Nao foi possivel ler %s: %s', ENV_FILE, exc)


_load_env_file()


def _default_database_url() -> str:
    """Fallback de desenvolvimento. Em producao, a ausencia de DATABASE_URL e erro."""
    if os.getenv('ENVIRONMENT', 'development').lower() == 'production':
        raise RuntimeError(
            'DATABASE_URL nao definida. Configure-a no .env '
            f'({ENV_FILE}) e garanta que a unit systemd tenha '
            'EnvironmentFile apontando para ele.'
        )
    url = f"sqlite:///{(BASE_DIR / 'infralab_dev.db').as_posix()}"
    logger.warning('DATABASE_URL nao definida; usando SQLite de desenvolvimento: %s', url)
    return url


class Settings(BaseModel):
    APP_NAME: str = os.getenv('APP_NAME', 'InfraLab Web API')
    APP_VERSION: str = os.getenv('APP_VERSION', '1.0.0')
    ENVIRONMENT: str = os.getenv('ENVIRONMENT', 'development')
    DEBUG: bool = os.getenv('DEBUG', 'False').lower() == 'true'
    HOST: str = os.getenv('HOST', '127.0.0.1')
    PORT: int = int(os.getenv('PORT', '8000'))
    # "or" trata DATABASE_URL vazia como ausente
    DATABASE_URL: str = os.getenv('DATABASE_URL') or _default_database_url()
    ALLOWED_ORIGINS: str = os.getenv('ALLOWED_ORIGINS', '*')


settings = Settings()
