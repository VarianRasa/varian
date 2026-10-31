from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tool.check_markdown_links import broken_links


class MarkdownLinksTest(unittest.TestCase):
    def test_existing_file_directory_and_anchors_pass(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "docs").mkdir()
            (root / "docs" / "guide.md").write_text("# Guide", encoding="utf-8")
            document = root / "AGENTS.md"
            document.write_text(
                "[directory](docs/) [guide](docs/guide.md#guide) [anchor](#setup)",
                encoding="utf-8",
            )
            self.assertEqual([], broken_links(document, root))

    def test_missing_target_and_escape_fail(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            document = root / "AGENTS.md"
            document.write_text("[missing](missing.md) [escape](../outside.md)", encoding="utf-8")
            errors = broken_links(document, root)
            self.assertEqual(2, len(errors))
            self.assertIn("missing link target", errors[0])
            self.assertIn("escapes the repository", errors[1])

    def test_external_links_are_not_fetched(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            document = root / "AGENTS.md"
            document.write_text(
                "[web](https://example.test/page) [email](mailto:qa@example.test)",
                encoding="utf-8",
            )
            self.assertEqual([], broken_links(document, root))


if __name__ == "__main__":
    unittest.main()
