import os
from fastapi import FastAPI, Request, status
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from app.config import settings
from app.database import engine, Base
from app.routes.health import router as health_router
from app.routes.items import router as items_router
import time
import logging

# Logger do uvicorn: aparece no journalctl mesmo sem configuração extra de logging
logger = logging.getLogger('uvicorn.error')
logger.info('Banco de dados em uso: %s', engine.url.render_as_string(hide_password=True))

# Criação das tabelas no banco de dados.
# Se o banco estiver indisponível, a API sobe mesmo assim e /health/ready
# reporta 503, em vez de entrar em loop de crash no systemd.
try:
    Base.metadata.create_all(bind=engine)
except Exception as exc:
    logger.error('Falha ao criar/verificar tabelas no banco: %s', exc)

app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="Servidor Web Linux - Componente InfraLab (Responsável: Paulo). API backend desenvolvida com FastAPI, Uvicorn, SQLAlchemy e PostgreSQL.",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json"
)

# Configuração de CORS
origins = [origin.strip() for origin in settings.ALLOWED_ORIGINS.split(',') if origin.strip()]
if not origins:
    origins = ['*']
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials='*' not in origins,  # CORS não permite credenciais com origem "*"
    allow_methods=['*'],
    allow_headers=['*'],
)

# Middleware para cabeçalho de tempo de processamento
@app.middleware('http')
async def add_process_time_header(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time
    response.headers['X-Process-Time'] = f'{process_time:.4f}s'
    return response

# Tratamento global de exceções não capturadas
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            'detail': 'Erro interno do servidor.',
            'error': str(exc) if settings.DEBUG else 'Consulte os logs do servidor.'
        }
    )

# Registrar roteadores
app.include_router(health_router)
app.include_router(items_router)

# Servir arquivos estáticos do Frontend em /app
frontend_path = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../frontend'))
if os.path.exists(frontend_path):
    app.mount('/app', StaticFiles(directory=frontend_path, html=True), name='frontend')


@app.get('/', tags=['Raíz'])
def root():
    """Endpoint principal com informações básicas da aplicação."""
    return {
        'name': settings.APP_NAME,
        'version': settings.APP_VERSION,
        'status': 'online',
        'documentation': '/docs',
        'healthcheck': '/health'
    }
