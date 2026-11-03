#!/usr/bin/env python3
"""Says whether a change needs the desktop AX cases in Scripts/test-provider-accessibility.py.

Compares the working tree, including untracked files, with where this branch left the default branch.
Exit 0: run them. Exit 10: no change touches what they cover. Anything unknown means run them.
"""
import subprocess
import sys

BASE_REF = "origin/main"
NOT_NEEDED_EXIT_CODE = 10
# What Tests/AXFixture renders, and the cases themselves. A path ending in a partial name covers
# every file that starts with it.
COVERED_PATHS = (
    "VLMSnapper/UI/ManagementCenterView.swift",
    "VLMSnapper/UI/BilingualResultView.swift",
    "VLMSnapper/UI/History",
    "VLMSnapper/UI/Provider",
    "Tests/AXFixture/",
    "Scripts/test-provider-accessibility.py",
)


def git(*arguments):
    completed = subprocess.run(["git", *arguments], capture_output=True, text=True, check=True)
    return completed.stdout.splitlines()


def changed_paths():
    base = git("merge-base", "HEAD", BASE_REF)[0]
    return git("diff", "--name-only", "--no-renames", base) + git("ls-files", "--others", "--exclude-standard")


def covered(paths):
    return [path for path in paths if path.startswith(COVERED_PATHS)]


def main():
    try:
        touched = covered(changed_paths())
    except (subprocess.CalledProcessError, IndexError, OSError) as error:
        print(f"Desktop AX cases needed: cannot compare with {BASE_REF} ({error})")
        return 0
    if touched:
        print("Desktop AX cases needed: " + ", ".join(touched))
        return 0
    return NOT_NEEDED_EXIT_CODE


if __name__ == "__main__":
    sys.exit(main())
