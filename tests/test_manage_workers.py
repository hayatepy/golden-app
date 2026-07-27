"""Protect the nested Pywrangler launcher from host Python overrides."""

from types import SimpleNamespace

import manage_workers


def test_launcher_removes_inherited_uv_python(monkeypatch):
    monkeypatch.setenv("UV_PYTHON", "3.13.11")
    monkeypatch.setattr(manage_workers, "_node_version", lambda: "v24.18.0")
    monkeypatch.setattr(manage_workers.shutil, "which", lambda name: f"/bin/{name}")
    observed: dict[str, object] = {}

    def run(command, **kwargs):
        observed["command"] = command
        observed["environment"] = kwargs["env"]
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(manage_workers.subprocess, "run", run)

    assert manage_workers.main(["dev"]) == 0
    environment = observed["environment"]
    assert isinstance(environment, dict)
    assert observed["command"] == ["/bin/pywrangler", "dev"]
    assert "UV_PYTHON" not in environment
    assert environment["CREATE_HAYATE_REAL_NODE"] == "/bin/node"
    assert manage_workers.os.environ["UV_PYTHON"] == "3.13.11"
