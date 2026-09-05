"""Verify that staged APKs contain exactly their advertised native architectures."""

import argparse
import zipfile
from pathlib import Path


def verify(directory: Path, tag: str) -> None:
    abis = {"arm64-v8a", "armeabi-v7a", "x86_64"}
    for suffix in ("android", *sorted(abis)):
        apk = directory / f"hormone-{tag}-{suffix}.apk"
        expected = abis if suffix == "android" else {suffix}
        with zipfile.ZipFile(apk) as archive:
            entries = set(archive.namelist())
            actual = {name.split('/')[1] for name in entries
                      if name.startswith('lib/') and name.endswith('.so')}
            if actual != expected:
                raise ValueError(f"{apk.name}: expected {expected}, got {actual}")
            for abi in expected:
                for library in ("libflutter.so", "libapp.so"):
                    if f"lib/{abi}/{library}" not in entries:
                        raise ValueError(f"{apk.name}: missing {abi}/{library}")
        print(f"{apk.name}: {apk.stat().st_size / 1024 / 1024:.2f} MiB; ABI verified")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path("build/release"))
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    verify(args.directory, args.tag)
