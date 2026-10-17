import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from review_packet import build

class ReviewPacketTest(unittest.TestCase):
    def test_large_diff_has_complete_inventory_and_bounded_packet(self):
        prior = Path.cwd()
        with tempfile.TemporaryDirectory() as folder:
            os.chdir(folder)
            try:
                def run(*args):
                    return subprocess.check_output(["git", *args], stderr=subprocess.DEVNULL).decode().strip()
                run("init", "-q")
                run("config", "user.email", "fixture@example.test")
                run("config", "user.name", "Fixture")
                Path("README.md").write_text("baseline")
                run("add", ".")
                run("commit", "-qm", "baseline")
                base = run("rev-parse", "HEAD")
                Path("docs").mkdir()
                for index in range(350):
                    Path("docs", str(index) + ".md").write_text("evidence" * 100)
                Path("lib").mkdir()
                Path("lib/source.ex").write_text("new source\n" * 100)
                Path("test").mkdir()
                Path("test/source_test.exs").write_text("test")
                run("add", ".")
                run("commit", "-qm", "fixture")
                packet, patch = build(base, run("rev-parse", "HEAD"), "feat!: typed contract", max_lines=20)
                self.assertEqual(packet["summary"]["total_files"], 352)
                self.assertEqual(packet["summary"]["docs_files"], 350)
                self.assertEqual(packet["summary"]["source_files"], 1)
                self.assertEqual(packet["summary"]["test_files"], 1)
                self.assertEqual(packet["status"], "ok")
                self.assertLessEqual(len(patch.splitlines()), 20)
                self.assertEqual(packet["missing_signals"], [])
                rejected, _ = build(base, run("rev-parse", "HEAD"), "invalid title")
                self.assertEqual(rejected["status"], "error")
            finally:
                os.chdir(prior)

if __name__ == "__main__":
    unittest.main()
