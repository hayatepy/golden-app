"""Keep the class and global Workerd workloads identical except for entry mode."""

import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_class_and_global_wrangler_configs_share_the_same_workload():
    class_config = tomllib.loads((ROOT / "wrangler.toml").read_text(encoding="utf-8"))
    global_config = tomllib.loads((ROOT / "wrangler.global.toml").read_text(encoding="utf-8"))

    assert class_config["main"] == "src/entry.py"
    assert global_config["main"] == "src/entry_global.py"
    assert class_config["compatibility_flags"] == ["python_workers"]
    assert global_config["compatibility_flags"] == [
        "python_workers",
        "disable_python_no_global_handlers",
    ]

    for key in (
        "compatibility_date",
        "vars",
        "d1_databases",
        "ratelimits",
        "env",
        "python_modules",
    ):
        assert global_config[key] == class_config[key]
