from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker, declarative_base
from app.config import settings
import logging

logger = logging.getLogger(__name__)

connect_args = {}
if settings.DATABASE_URL.startswith('sqlite'):
    connect_args['check_same_thread'] = False

engine = create_engine(
    settings.DATABASE_URL,
    connect_args=connect_args,
    pool_pre_ping=True
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    """Gerador de sessão de banco de dados por requisição HTTP."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def check_database_connection() -> bool:
    """Verifica se a conexão com o banco de dados está funcional."""
    try:
        with engine.connect() as connection:
            connection.execute(text('SELECT 1'))
        return True
    except Exception as e:
        logger.error(f'Falha na conexão com o banco de dados: {e}')
        return False
