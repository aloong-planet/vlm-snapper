#!/usr/bin/env python3
"""Verify the single-version contract of a generated, one-item Sparkle feed."""

import sys
import xml.etree.ElementTree as ET


def main():
    if len(sys.argv) != 3:
        print("Usage: verify-appcast-version.py <appcast> <version>", file=sys.stderr)
        return 64
    path, expected = sys.argv[1:]
    try:
        root = ET.parse(path).getroot()
        items = root.findall("./channel/item")
        if root.tag != "rss" or len(items) != 1:
            raise ValueError("expected exactly one release item")
        namespace = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
        enclosures = items[0].findall("enclosure")
        if len(enclosures) != 1:
            raise ValueError("expected exactly one update enclosure")
        versions = [node.text for node in items[0].findall(namespace + "version")]
        display_versions = [node.text for node in items[0].findall(namespace + "shortVersionString")]
        for key, values in (("version", versions), ("shortVersionString", display_versions)):
            if namespace + key in enclosures[0].attrib:
                values.append(enclosures[0].attrib[namespace + key])
        if len(versions) != 1 or versions[0] != expected:
            raise ValueError("sparkle:version must match the App version")
        if len(display_versions) > 1 or any(value != expected for value in display_versions):
            raise ValueError("sparkle:shortVersionString must match the App version when present")
    except (OSError, ET.ParseError, ValueError) as error:
        print(f"Invalid appcast version: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
