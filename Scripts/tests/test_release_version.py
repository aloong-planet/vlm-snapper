"""Release CLI contracts; no builds, credentials, or network calls required.

XML shapes follow Sparkle Resources/SampleAppcast.xml and SUAppcastTest.swift.
These fixtures do not verify notarization or a public Sparkle update round trip;
those require a signed three-architecture release and a separately approved feed.
"""

import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class ReleaseVersionTests(unittest.TestCase):
    def test_enclosure_cannot_override_the_checked_version(self):
        result = self.verify_feed(
            "<sparkle:version>0.1.1</sparkle:version>",
            'sparkle:version="51"',
        )
        self.assertEqual(result.returncode, 1, result.stderr)

    def test_three_part_versions_are_accepted(self):
        for version in ("0.0.0", "0.1.1", "1.10.2", "12.34.56"):
            with self.subTest(version=version):
                result = subprocess.run(
                    ["bash", str(ROOT / "Scripts/validate-release-version.sh"), version],
                    capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_build_and_verify_reject_invalid_versions_before_artifact_work(self):
        commands = [
            ["build-macos-app.sh", "arm64", "51", "feed", "key", "/unused"],
            ["verify-macos-app.sh", "/unused", "arm64", "51", "feed", "key"],
            ["build-development-dmgs.sh"],
        ]
        for name, *arguments in commands:
            with self.subTest(script=name):
                result = subprocess.run(
                    ["bash", str(ROOT / "Scripts" / name), *arguments],
                    env={**os.environ, "VERSION": "51"},
                    capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertIn("MAJOR.MINOR.PATCH", result.stderr)

    def test_generated_appcast_uses_the_same_version(self):
        for content in (
            "<sparkle:version>0.1.1</sparkle:version>",
            "<sparkle:version>0.1.1</sparkle:version>"
            "<sparkle:shortVersionString>0.1.1</sparkle:shortVersionString>",
        ):
            with self.subTest(content=content):
                self.assertEqual(self.verify_feed(content).returncode, 0)
        self.assertEqual(self.verify_feed(
            "", 'sparkle:version="0.1.1" sparkle:shortVersionString="0.1.1"'
        ).returncode, 0)
        self.assertEqual(self.verify_feed(
            "<sparkle:version>0.1.1</sparkle:version>",
            'sparkle:shortVersionString="51"',
        ).returncode, 1)

    def test_inconsistent_missing_and_duplicate_appcast_versions_are_rejected(self):
        for content in (
            "", "<sparkle:version>51</sparkle:version>",
            "<version>0.1.1</version>",
            "<sparkle:version>0.1.1</sparkle:version>" * 2,
            "<sparkle:version>0.1.1</sparkle:version>"
            "<sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>",
            "<sparkle:version>0.1.1</sparkle:version>"
            + "<sparkle:shortVersionString>0.1.1</sparkle:shortVersionString>" * 2,
            "<sparkle:version>0.1.1</sparkle:version></item><item>"
            "<sparkle:version>0.1.1</sparkle:version>",
            "<broken",
        ):
            with self.subTest(content=content):
                result = self.verify_feed(content)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertIn("Invalid appcast version", result.stderr)

    def verify_feed(self, item_content, enclosure_attributes=""):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            path.write_text(
                '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
                '<channel><item><title>Version 0.1.1</title>' + item_content
                + '<enclosure url="https://updates.invalid/app.dmg" length="123" '
                'type="application/octet-stream" ' + enclosure_attributes
                + ' /></item></channel></rss>'
            )
            return subprocess.run(
                [sys.executable, str(ROOT / "Scripts/verify-appcast-version.py"), str(path), "0.1.1"],
                capture_output=True, text=True, check=False,
            )

    def test_invalid_versions_stop_before_release_configuration(self):
        for version in ("", "51", "1.2", "1.2.3.4", "01.2.3", "1.2.3-ci", "1.2.3\n"):
            with self.subTest(version=version):
                env = os.environ.copy()
                env.pop("MACOS_SIGNING_IDENTITY", None)
                result = subprocess.run(
                    ["bash", str(ROOT / "Scripts/release-macos.sh"), version,
                     "https://updates.invalid", "https://downloads.invalid", "key", "/unused"],
                    env=env, capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertIn("MAJOR.MINOR.PATCH", result.stderr)


if __name__ == "__main__":
    unittest.main()
