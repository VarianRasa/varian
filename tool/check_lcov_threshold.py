from __future__ import annotations

import argparse
from pathlib import Path


def line_coverage(path: Path) -> tuple[int, int]:
    lines_hit = 0
    lines_found = 0
    in_record = False

    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("SF:"):
            in_record = True
        elif in_record and line.startswith("LF:"):
            lines_found += int(line[3:])
        elif in_record and line.startswith("LH:"):
            lines_hit += int(line[3:])
        elif line == "end_of_record":
            in_record = False

    if lines_found == 0:
        raise ValueError(f"No executable source lines found in {path}.")
    if lines_hit > lines_found:
        raise ValueError(f"Coverage hits exceed executable lines in {path}.")
    return lines_hit, lines_found


def main() -> int:
    parser = argparse.ArgumentParser(description="Enforce a minimum LCOV line coverage.")
    parser.add_argument("lcov_file", type=Path)
    parser.add_argument("--minimum", type=float, required=True)
    args = parser.parse_args()
    if not 0 <= args.minimum <= 100:
        parser.error("--minimum must be between 0 and 100")

    hit, found = line_coverage(args.lcov_file)
    percent = hit * 100 / found
    print(f"Line coverage: {percent:.2f}% ({hit}/{found}); required: {args.minimum:.2f}%")
    return 0 if percent >= args.minimum else 1


if __name__ == "__main__":
    raise SystemExit(main())
