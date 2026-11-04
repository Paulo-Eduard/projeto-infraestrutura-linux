import os
from pydantic import BaseModel

class Settings(BaseModel):
    APP_NAME: str = os.getenv('APP_NAME', 'InfraLab Web API')
    APP_VERSION: str = os.getenv('APP_VERSION', '1.0.0')
    ENVIRONMENT: str = os.getenv('ENVIRONMENT', 'development')
    DEBUG: bool = os.getenv('DEBUG', 'True').lower() == 'true'
    HOST: str = os.getenv('HOST', '127.0.0.1')
    PORT: int = int(os.getenv('PORT', '8000'))
    DATABASE_URL: str = os.getenv('DATABASE_URL', 'sqlite:////workspace/scratch/infralab_dev.db')
    ALLOWED_ORIGINS: str = os.getenv('ALLOWED_ORIGINS', '*')

settings = Settings()
