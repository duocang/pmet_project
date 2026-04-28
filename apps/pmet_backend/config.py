from pathlib import Path
from dataclasses import dataclass

@dataclass
class Config:
    # Repo root: apps/backend/config.py -> ../../.. = repo root.
    PROJECT_ROOT: Path = Path(__file__).resolve().parent.parent.parent
    RESULT_DIR: Path = PROJECT_ROOT / "result"
    # Read-only catalog of pre-computed species/motif databases, populated by
    # pipeline/data/download_pmet_data.sh. Layout: <species>/<motif_db>/.
    PRECOMPUTED_INDEXING_DIR: Path = PROJECT_ROOT / "data" / "indexing"
    PRECOMPUTED_INDEXING_METADATA: Path = PROJECT_ROOT / "data" / "indexing_metadata.json"
    GENOME_METADATA: Path = PROJECT_ROOT / "data" / "genome_n_annotation.json"
    TASKS_DIR: Path = PROJECT_ROOT / "result" / "tasks"
    # Workflows + helpers (bash + python + R) live under pipeline/.
    # The "-r" flag the indexer takes equals str(SCRIPTS_DIR).
    SCRIPTS_DIR: Path = PROJECT_ROOT / "pipeline"
    # Repo root again — executor uses this for build/ and as the workflow base
    # path. Kept under the existing name to avoid a churn-y rename across the
    # executor and Dockerfile docs.
    PMET_SCRIPTS_DIR: Path = PROJECT_ROOT

    # Email configuration
    EMAIL_USERNAME: str = ""
    EMAIL_PASSWORD: str = ""
    EMAIL_ADDRESS: str = ""
    EMAIL_SERVER: str = ""
    EMAIL_PORT: str = ""

    # Server
    NCPU: int = 4
    NGINX_LINK: str = ""

    def __post_init__(self):
        self.RESULT_DIR.mkdir(parents=True, exist_ok=True)
        self.TASKS_DIR.mkdir(parents=True, exist_ok=True)
        self._load_configs()

    def _load_configs(self):
        cpu_file = self.PROJECT_ROOT / "data" / "configure" / "cpu_configuration.txt"
        if cpu_file.exists():
            self.NCPU = int(cpu_file.read_text().strip().split()[0])

        nginx_file = self.PROJECT_ROOT / "data" / "configure" / "nginx_link.txt"
        if nginx_file.exists():
            self.NGINX_LINK = nginx_file.read_text().strip()

        email_file = self.PROJECT_ROOT / "data" / "configure" / "email_credential.txt"
        if email_file.exists():
            lines = email_file.read_text().strip().split("\n")
            if len(lines) >= 5:
                self.EMAIL_USERNAME = lines[0].strip()
                self.EMAIL_PASSWORD = lines[1].strip()
                self.EMAIL_ADDRESS = lines[2].strip()
                self.EMAIL_SERVER = lines[3].strip()
                self.EMAIL_PORT = lines[4].strip()

config = Config()
