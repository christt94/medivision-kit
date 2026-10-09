from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    DEBUG: bool = True
    APP_NAME: str = "MediVision Kit"
    VERSION: str = "0.1.0"
    COUNTRY_CODE: str = "CM"
    SQLITE_PATH: str = "data/medivision.db"
    DUCKDB_PATH: str = "data/refs.duckdb"
    MODELS_DIR: str = "models"
    FILES_DIR: str = "data/files"
    SECRET_KEY: str = "change-me-in-production"
    SESSION_TIMEOUT_MIN: int = 15

    class Config:
        env_file = ".env"

settings = Settings()
