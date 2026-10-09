import asyncio, sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import aiosqlite
import duckdb

SQLITE_PATH = "data/medivision.db"
DUCKDB_PATH = "data/refs.duckdb"

SQLITE_SCHEMA = """
CREATE TABLE IF NOT EXISTS patients (
    id TEXT PRIMARY KEY,
    nom TEXT NOT NULL,
    prenom TEXT NOT NULL,
    sexe TEXT CHECK(sexe IN ('M','F','A')),
    date_nais DATE,
    identifiant_externe TEXT,
    pays_code TEXT DEFAULT 'CM',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME,
    deleted_at DATETIME
);
CREATE TABLE IF NOT EXISTS examens (
    id TEXT PRIMARY KEY,
    patient_id TEXT REFERENCES patients(id),
    modalite TEXT NOT NULL,
    indication TEXT,
    operateur_id TEXT,
    qualite TEXT,
    fichier_path TEXT,
    metadata TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS rapports (
    id TEXT PRIMARY KEY,
    examen_id TEXT REFERENCES examens(id),
    statut TEXT DEFAULT 'BROUILLON',
    contenu_json TEXT,
    contenu_pdf_path TEXT,
    diagnostic_cim11 TEXT,
    validateur_id TEXT,
    validated_at DATETIME,
    version INTEGER DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS audit_log (
    id TEXT PRIMARY KEY,
    timestamp DATETIME NOT NULL,
    utilisateur TEXT NOT NULL,
    action TEXT NOT NULL,
    ressource TEXT NOT NULL,
    hash_prev TEXT,
    hash_entry TEXT NOT NULL
);
"""

async def init_sqlite():
    os.makedirs(os.path.dirname(SQLITE_PATH), exist_ok=True)
    async with aiosqlite.connect(SQLITE_PATH) as db:
        await db.executescript(SQLITE_SCHEMA)
        await db.commit()
    print(f"  ✓ SQLite initialized → {SQLITE_PATH}")

def init_duckdb():
    os.makedirs(os.path.dirname(DUCKDB_PATH), exist_ok=True)
    con = duckdb.connect(DUCKDB_PATH)
    con.execute("""
        CREATE TABLE IF NOT EXISTS oms_mlem (
            dci TEXT PRIMARY KEY,
            classe_oms TEXT,
            forme TEXT,
            dosage TEXT,
            voie TEXT,
            indication TEXT,
            cim11_code TEXT,
            pediatrique BOOLEAN DEFAULT FALSE,
            version_liste TEXT
        );
    """)
    con.execute("""
        CREATE TABLE IF NOT EXISTS lnme_pays (
            pays_code TEXT,
            dci TEXT,
            disponible BOOLEAN DEFAULT TRUE,
            nom_commercial TEXT,
            prix_indicatif REAL,
            PRIMARY KEY (pays_code, dci)
        );
    """)
    con.close()
    print(f"  ✓ DuckDB initialized  → {DUCKDB_PATH}")

async def main():
    print("Initializing MediVision Kit databases...")
    await init_sqlite()
    init_duckdb()
    print("✓ All databases ready.")

asyncio.run(main())
