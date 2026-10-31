"""Check repository-local Markdown links without making network requests."""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from urllib.parse import unquote, urlsplit

LINK = re.compile(r"\[[^\]]*\]\(([^\s)]+)\)")


def broken_links(document: Path, repository_root: Path) -> list[str]:
    errors = []
    for match in LINK.finditer(document.read_text(encoding="utf-8")):
        reference = urlsplit(match.group(1))
        if reference.scheme or reference.netloc or not reference.path:
            continue
        target = (document.parent / unquote(reference.path)).resolve()
        if not target.is_relative_to(repository_root.resolve()):
            errors.append(f"{document}: link escapes the repository: {match.group(1)}")
        elif not target.exists():
            errors.append(f"{document}: missing link target: {match.group(1)}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("documents", nargs="+", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    errors = []
    for document in args.documents:
        errors.extend(broken_links(document, root))
    for error in errors:
        print(error)
    if errors:
        return 1
    print(f"Checked local links in {len(args.documents)} document(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
