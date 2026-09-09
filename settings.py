"""Language preferences stored separately from existing version-1 rule files."""
import contextlib
import json
import os
from pathlib import Path
import tempfile

from i18n import DEFAULT_LANGUAGE, LANGUAGES, LocalizedError


class Settings:
    def __init__(self, path):
        self.path = Path(path)

    def load(self):
        if not self.path.exists():
            return {}
        data = json.loads(self.path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise LocalizedError("Unsupported settings format")
        return data

    def language(self):
        value = self.load().get("language")
        return value if isinstance(value, str) and value in LANGUAGES else DEFAULT_LANGUAGE

    def save_language(self, language):
        if language not in LANGUAGES:
            raise LocalizedError("Unsupported language")
        data = self.load()  # Preserve other preferences and refuse to overwrite corrupt files.
        data["language"] = language
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, name = tempfile.mkstemp(prefix=".settings-", dir=self.path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                json.dump(data, handle, ensure_ascii=False, indent=2)
                handle.write("\n")
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(name, self.path)
        finally:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(name)
