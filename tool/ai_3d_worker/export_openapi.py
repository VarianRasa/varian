from __future__ import annotations

import argparse
import json
from pathlib import Path

from .app import app

SCHEMA_PATH = Path(__file__).with_name("openapi.json")


def render_schema() -> str:
    return json.dumps(app.openapi(), indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate or verify the worker OpenAPI document.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail if the checked-in document differs from the current FastAPI schema.",
    )
    args = parser.parse_args()
    rendered = render_schema()

    if args.check:
        if not SCHEMA_PATH.exists() or SCHEMA_PATH.read_text(encoding="utf-8") != rendered:
            parser.error(
                "OpenAPI document is stale; regenerate it with this command without --check."
            )
        print(f"OpenAPI document is current: {SCHEMA_PATH}")
        return 0

    SCHEMA_PATH.write_text(rendered, encoding="utf-8")
    print(f"Wrote OpenAPI document: {SCHEMA_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
