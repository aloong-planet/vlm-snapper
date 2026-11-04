#!/usr/bin/env python3
"""Verify that every language's dictionary has the same keys, and the keys the code names exist."""

import argparse
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ENTRY = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.S)
SPECIFIER = re.compile(r"%(?:(\d+)\$)?[-+#0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?([@a-zA-Z%])")
# `forKey:` alone also matches UserDefaults keys, so it counts only after localizedString.
NAMED_KEY = re.compile(r'(?:\blocalized\(\s*|\blocalizedString\(\s*forKey:\s*)"([^"\\]+)"')
DOTTED_LITERAL = re.compile(r'"([a-z][A-Za-z]*(?:\.[A-Za-z0-9]+)+)"')
# This file maps failure codes to keys through bare literals, so every dotted literal in it is a key.
STRINGS_FILE = "VLMSnapperStrings.swift"


def without_comments(text):
    """Removes comments, leaving a // or /* inside a string alone."""
    result = []
    index = 0
    while index < len(text):
        if text[index] == '"':
            end = index + 1
            while end < len(text) and text[end] != '"':
                end += 2 if text[end] == "\\" else 1
            result.append(text[index:end + 1])
            index = end + 1
        elif text.startswith("/*", index):
            end = text.find("*/", index + 2)
            index = len(text) if end < 0 else end + 2
        elif text.startswith("//", index):
            end = text.find("\n", index)
            index = len(text) if end < 0 else end
        else:
            result.append(text[index])
            index += 1
    return "".join(result)


def read_dictionary(path, problems):
    try:
        text = without_comments(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError) as error:
        problems.append(f"Cannot read {path}: {error}")
        return {}
    entries = {}
    for key, value in ENTRY.findall(text):
        if key in entries:
            problems.append(f"{path}: duplicate key {key}")
        entries[key] = value
    leftover = ENTRY.sub("", text).strip()
    if leftover:
        problems.append(f"{path}: cannot read an entry near {leftover[:60]!r}")
    return entries


def specifiers(value):
    """The argument each position takes, so that a translation may reorder positional arguments."""
    arguments = {}
    next_position = 1
    for position, kind in SPECIFIER.findall(value):
        if kind == "%":
            continue
        if position:
            arguments[int(position)] = kind
        else:
            arguments[next_position] = kind
            next_position += 1
    return arguments


def named_keys(sources):
    names = {}
    for directory in sources:
        for path in sorted(directory.rglob("*.swift")):
            text = path.read_text(encoding="utf-8")
            found = set(NAMED_KEY.findall(text))
            if path.name == STRINGS_FILE:
                found.update(DOTTED_LITERAL.findall(text))
            for key in found:
                names.setdefault(key, path)
    return names


def check(dictionaries, sources):
    problems = []
    languages = {
        directory.name.removesuffix(".lproj"): read_dictionary(directory / "Localizable.strings", problems)
        for directory in sorted(dictionaries.glob("*.lproj"))
    }
    if len(languages) < 2:
        problems.append(f"{dictionaries}: fewer than two languages to compare")
        return problems
    all_keys = set().union(*languages.values())
    for language, entries in languages.items():
        for key in sorted(all_keys - entries.keys()):
            problems.append(f"{language}: missing key {key}")
    for key in sorted(all_keys):
        forms = {language: specifiers(entries[key]) for language, entries in languages.items() if key in entries}
        if len({tuple(sorted(form.items())) for form in forms.values()}) > 1:
            problems.append(f"{key}: format specifiers differ: {forms}")
    for key, path in sorted(named_keys(sources).items()):
        if key not in all_keys:
            problems.append(f"{path}: names key {key}, which no dictionary has")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dictionaries", type=Path, default=ROOT / "VLMSnapper/Resources/Localization")
    parser.add_argument("--sources", type=Path, nargs="+", default=[ROOT / "Sources", ROOT / "VLMSnapper"])
    args = parser.parse_args()
    problems = check(args.dictionaries, args.sources)
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
