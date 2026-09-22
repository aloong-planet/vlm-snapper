#!/usr/bin/env python3
"""Verify that a successful swift test process actually finished Swift Testing."""

import argparse
from pathlib import Path
import re
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    args = parser.parse_args()
    try:
        content = args.log.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        print(f"Cannot read test log: {error}", file=sys.stderr)
        return 1
    lines = content.splitlines()
    starts = [index for index, line in enumerate(lines) if line == "◇ Test run started."]
    finishes = [
        index for index, line in enumerate(lines)
        if re.fullmatch(
            r"✔ Test run with [1-9][0-9]* tests?(?: in [1-9][0-9]* suites?)? "
            r"passed after [0-9]+(?:\.[0-9]+)? seconds\.", line
        )
    ]
    if len(starts) != 1 or len(finishes) != 1 or starts[0] >= finishes[0]:
        print("Swift Testing did not report one complete, nonempty successful run.", file=sys.stderr)
        return 1
    if any(line.startswith(("◇ Test ", "◇ Suite ", "✘")) for line in lines[finishes[0] + 1:]):
        print("Test activity continued after the completion report.", file=sys.stderr)
        return 1
    print(lines[finishes[0]])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
