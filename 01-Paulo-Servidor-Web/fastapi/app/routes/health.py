from fastapi import APIRouter, Response, status
from datetime import datetime, timezone
from app.config import settings
from app.database import check_database_connection

router = APIRouter(tags=['Saúde e Diagnóstico'])

@router.get('/health', status_code=status.HTTP_200_OK)
def get_health():
    """Rota rápida de checagem do estado do backend."""
    return {
        'status': 'healthy',
        'service': settings.APP_NAME,
        'version': settings.APP_VERSION,
        'timestamp': datetime.now(timezone.utc).isoformat()
    }

@router.get('/health/ready')
def get_readiness(response: Response):
    """Rota de prontidão: valida a conectividade com o banco de dados."""
    db_ok = check_database_connection()
    if db_ok:
        return {
            'status': 'ready',
            'database': 'connected',
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
    else:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {
            'status': 'unhealthy',
            'database': 'disconnected',
            'error': 'Falha ao conectar com o banco de dados PostgreSQL/SQLite',
            'timestamp': datetime.now(timezone.utc).isoformat()
        }
