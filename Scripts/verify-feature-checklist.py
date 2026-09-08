#!/usr/bin/env python3
"""Check requirement ownership; this does not certify implementation acceptance."""

import argparse
from collections import Counter
from pathlib import Path
import re
import sys


def verify(document):
    expected = {f"US-{number:02d}" for number in range(1, 13)}
    expected.update(f"FM-{number:02d}" for number in range(1, 47))
    sections = re.findall(r"^## Spec requirement ownership\s*\n(.*?)(?=^## |\Z)", document, re.MULTILINE | re.DOTALL)
    if len(sections) != 1:
        raise ValueError("Expected one Spec requirement ownership section")
    rows = []
    for line in sections[0].splitlines():
        if not re.match(r"^\s*\|\s*(?:US|FM)-", line):
            continue
        cells = [cell.strip() for cell in line.strip().split("|")]
        identifier = cells[1]
        if len(cells) != 6 or cells[0] or cells[-1] or not all(cells[1:5]):
            raise ValueError(f"{identifier}: expected four nonempty cells (ID, requirement, owner, criterion)")
        rows.append(identifier)
    counts = Counter(rows)
    duplicates = {identifier for identifier, count in counts.items() if count > 1}
    if duplicates:
        raise ValueError("Duplicate requirements: " + ", ".join(sorted(duplicates)))
    identifiers = set(counts)
    unexpected = identifiers - expected
    if unexpected:
        raise ValueError("Unexpected requirements: " + ", ".join(sorted(unexpected)))
    missing = expected - identifiers
    if missing:
        raise ValueError("Missing requirements: " + ", ".join(sorted(missing)))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checklist", type=Path)
    args = parser.parse_args()
    try:
        verify(args.checklist.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print("Checklist ownership passed: 58 requirements")
    return 0


if __name__ == "__main__":
    sys.exit(main())
