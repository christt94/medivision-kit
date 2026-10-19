from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Local development remains zero-config; set DEBUG=false in deployments.
    DEBUG: bool = True
    APP_NAME: str = "MediVision Kit"
    VERSION: str = "0.1.0"
    COUNTRY_CODE: str = "CM"
    SQLITE_PATH: str = "data/medivision.db"
    DUCKDB_PATH: str = "data/refs.duckdb"
    MODELS_DIR: str = "models"
    FILES_DIR: str = "data/files"
    SECRET_KEY: str = ""
    SESSION_TIMEOUT_MIN: int = 15
    CORS_ORIGINS: str = "http://localhost:3000,http://127.0.0.1:3000"
    MAX_UPLOAD_BYTES: int = 50 * 1024 * 1024
    IMAGING_MODEL: str = "none"

    class Config:
        env_file = ".env"

settings = Settings()
