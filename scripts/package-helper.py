#!/usr/bin/env python3
"""Package self-contained publish outputs; never publish or modify the plugin pin."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile


PLATFORMS = (
    "osx-x64", "osx-arm64", "linux-x64", "linux-arm64", "win-x64", "win-arm64"
)


def package(publish_dir: Path, output_dir: Path, release: str, helper: str = "main") -> None:
    """Require one executable per RID, then atomically create assets and manifest."""
    if not re.fullmatch(r"helper-v\d+\.\d+\.\d+", release):
        raise ValueError("Release must be an immutable helper-vMAJOR.MINOR.PATCH tag")
    if output_dir.exists():
        raise ValueError("Output already exists; do not overwrite release artifacts")
    if not publish_dir.is_dir():
        raise ValueError("Publish directory does not exist")
    directories = list(publish_dir.iterdir())
    if not directories:
        raise ValueError("No published helper executables found")
    for directory in directories:
        if not directory.is_dir() or directory.name not in PLATFORMS:
            raise ValueError(f"Unsupported publish target: {directory.name}")
    if helper not in ("main", "postgres"):
        raise ValueError("Unsupported helper family")
    manifest = {"schema": 1, "release": release, "artifacts": {}}
    if helper == "postgres":
        manifest["helper"] = "postgres"
    prefix = "enhance-helper-postgres" if helper == "postgres" else "enhance-helper"
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="enhance-package-", dir=output_dir.parent) as temp:
        staging = Path(temp) / "assets"
        staging.mkdir()
        for directory in sorted(directories):
            rid = directory.name
            suffix = ".exe" if rid.startswith("win-") else ""
            executable = directory / (prefix + suffix)
            # A single-file bundle must not silently omit native/runtime dependencies.
            if not executable.is_file() or executable.is_symlink():
                raise ValueError(f"Missing executable: {executable}")
            sidecars = [path for path in directory.iterdir() if path != executable]
            if sidecars:
                raise ValueError(f"Publish {rid} is not single-file; unexpected sidecars")
            if executable.stat().st_size == 0:
                raise ValueError(f"Empty executable: {executable}")
            if executable.stat().st_size > 209715200:
                raise ValueError(f"Executable exceeds installer size limit: {executable}")
            asset_name = prefix + "-" + rid + suffix
            asset = staging / asset_name
            shutil.copyfile(executable, asset)
            if not suffix:
                asset.chmod(0o700)
            with asset.open("rb") as stream:
                hasher = hashlib.sha256()
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    hasher.update(chunk)
                digest = hasher.hexdigest()
            manifest["artifacts"][rid] = {"name": asset_name, "sha256": digest}
        (staging / "helper-release.json").write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
        )
        staging.rename(output_dir)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--release", required=True)
    parser.add_argument("--helper", choices=("main", "postgres"), default="main")
    args = parser.parse_args()
    try:
        package(args.publish_dir, args.output_dir, args.release, args.helper)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Packaging failed: {error}\n")


if __name__ == "__main__":
    main()
