"""Create checksums and a GitHub-compatible update manifest from staged APKs."""

import argparse
import hashlib
import json
import re
from pathlib import Path


def prepare(directory: Path, tag: str, notes: str) -> dict:
    if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        raise ValueError("A stable vX.Y.Z tag is required")
    release_url = f"https://github.com/Aetik-yue/hormone/releases"
    assets = []
    # Universal first, preserving the selection behavior of pre-optimization apps.
    for abi in ("android", "arm64-v8a", "armeabi-v7a", "x86_64"):
        name = f"hormone-{tag}-{abi}.apk"
        apk = directory / name
        with apk.open("rb") as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        (directory / f"{name}.sha256").write_text(
            f"{digest}  {name}\n", encoding="utf-8"
        )
        assets.append({
            "name": name,
            "browser_download_url": f"{release_url}/download/{tag}/{name}",
            "size": apk.stat().st_size,
            "digest": f"sha256:{digest}",
        })
    manifest = {
        "tag_name": tag,
        "name": f"Hormone {tag}",
        "html_url": f"{release_url}/tag/{tag}",
        "body": notes,
        "draft": False,
        "prerelease": False,
        "assets": assets,
    }
    (directory / "latest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path("build/release"))
    parser.add_argument("--tag", required=True)
    parser.add_argument("--notes", type=Path)
    args = parser.parse_args()
    notes_path = args.notes or Path("version") / args.tag.removeprefix("v") / "更新日志.md"
    notes = notes_path.read_text(encoding="utf-8") if notes_path.exists() else ""
    prepare(args.directory, args.tag, notes)
