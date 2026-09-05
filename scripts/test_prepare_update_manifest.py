import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from prepare_update_manifest import prepare


class UpdateManifestTest(unittest.TestCase):
    def test_release_assets_and_legacy_compatibility(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for abi in ("android", "arm64-v8a", "armeabi-v7a", "x86_64"):
                (root / f"hormone-v1.3.0-{abi}.apk").write_bytes(abi.encode())
            manifest = prepare(root, "v1.3.0", "更新内容")
            self.assertEqual(json.loads((root / "latest.json").read_text(encoding="utf-8")), manifest)
            self.assertEqual(len(manifest["assets"]), 4)
            # The old client prioritizes any APK with "android" in its filename.
            legacy = sorted(manifest["assets"], key=lambda a: "android" not in a["name"])[0]
            self.assertEqual(legacy["name"], "hormone-v1.3.0-android.apk")
            for asset in manifest["assets"]:
                data = (root / asset["name"]).read_bytes()
                digest = hashlib.sha256(data).hexdigest()
                self.assertEqual(asset["digest"], f"sha256:{digest}")
                self.assertEqual(asset["size"], len(data))
                self.assertEqual((root / f'{asset["name"]}.sha256').read_text().split()[0], digest)

    def test_missing_architecture_stops_manifest_publication(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "hormone-v1.3.0-android.apk").write_bytes(b"universal")
            with self.assertRaises(FileNotFoundError):
                prepare(root, "v1.3.0", "")
            self.assertFalse((root / "latest.json").exists())

    def test_unstable_or_invalid_tag_is_rejected(self):
        for tag in ("v1.3.0-beta", "../file", "1.3.0"):
            with self.assertRaises(ValueError):
                prepare(Path("unused"), tag, "")


if __name__ == "__main__":
    unittest.main()
