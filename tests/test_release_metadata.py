"""Keep the public scaffold provenance consistent across checked evidence."""

from __future__ import annotations

import re
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CREATE_HAYATE_REFERENCE = re.compile(r"create-hayate==(\d+\.\d+\.\d+)")
PUBLIC_HOME = "https://hayatepy.dev/"
PUBLIC_DEPLOY = "https://hayatepy.dev/deploy/"
PUBLIC_COMPATIBILITY = "https://hayatepy.dev/evidence/compatibility/"
SUPERSEDED_DOCS_PREFIX = "https://github.com/hayatepy/.github/blob/main/docs/"


def test_generator_release_matches_public_provenance_references() -> None:
    manifest = tomllib.loads((ROOT / "golden-app.toml").read_text(encoding="utf-8"))
    generator, version = str(manifest["generated_by"]).rsplit(" ", 1)

    assert generator == "create-hayate"
    for relative_path in ("README.md", "ARCHITECTURE.md"):
        references = set(
            CREATE_HAYATE_REFERENCE.findall((ROOT / relative_path).read_text(encoding="utf-8"))
        )
        assert references == {version}, (
            f"{relative_path} must reference exactly create-hayate=={version}"
        )


def test_readme_routes_public_discovery_through_hayatepy_dev() -> None:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")

    assert PUBLIC_HOME in readme
    assert PUBLIC_DEPLOY in readme
    assert PUBLIC_COMPATIBILITY in readme
    assert SUPERSEDED_DOCS_PREFIX not in readme
