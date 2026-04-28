from pathlib import Path
from dataclasses import dataclass

@dataclass
class Config:
    PROJECT_ROOT: Path = Path(__file__).parent.parent
    RESULT_DIR: Path = PROJECT_ROOT / "result"
    # Read-only catalog of pre-computed species/motif databases, populated by
    # scripts/download_pmet_data.sh. Layout: <species>/<motif_db>/.
    PRECOMPUTED_INDEXING_DIR: Path = PROJECT_ROOT / "data" / "indexing"
    # Per-species record of parameters the indexes were built with
    # (promoter_length, utr5, overlap, etc.). Surfaced as read-only
    # "Fixed parameters" in the submit form. Re-read on every request.
    PRECOMPUTED_INDEXING_METADATA: Path = PROJECT_ROOT / "data" / "indexing_metadata.json"
    # External reference metadata: species description, genome/annotation
    # file names + download URLs, and the source URL for each motif database.
    # Used by the species/motif-DB detail panel in the submit form.
    GENOME_METADATA: Path = PROJECT_ROOT / "data" / "genome_n_annotation.json"
    # Each task lives under RESULT_DIR/<task_id>/{upload,indexing,pairing}/.
    # The frontend generates the task_id (a UUID) on submit-page mount and
    # reuses it for both the upload phase and the run phase, so all artefacts
    # for one submission share a single root.
    TASKS_DIR: Path = PROJECT_ROOT / "result" / "tasks"
    SCRIPTS_DIR: Path = PROJECT_ROOT / "scripts"
    PMET_SCRIPTS_DIR: Path = PROJECT_ROOT / "pmet_pipeline"

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
