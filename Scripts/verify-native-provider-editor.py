"""Build and run bounded native menu acceptance.

Exercises a real AppKit window/menu with fixture credentials and a private
pasteboard. This is not physical mouse automation or live Provider validation.
Each run is a fresh process. A zero launcher exit alone is never a pass.
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, help="Use an explicitly prebuilt binary (also for gate negative controls)")
    parser.add_argument("--runs", type=int, default=10)
    parser.add_argument("--timeout", type=float, default=20)
    args = parser.parse_args()
    if args.runs < 1 or not 0 < args.timeout <= 60:
        parser.error("runs must be positive and timeout must be in (0, 60]")
    root = Path(__file__).resolve().parent.parent
    if args.binary is None:
        try:
            build = subprocess.run(
                ["swift", "build", "--product", "VLMSnapperUIHarness", "-Xswiftc", "-warnings-as-errors"],
                cwd=root, capture_output=True, text=True, timeout=60,
            )
        except subprocess.TimeoutExpired:
            print(json.dumps({"stage": "build", "status": "timeout", "limit": 60}), flush=True)
            return 124
        if build.returncode:
            print(json.dumps({"stage": "build", "status": "fail", "output": build.stdout + build.stderr}), flush=True)
            return 1
    binary = (args.binary or root / ".build/debug/VLMSnapperUIHarness").resolve(strict=True)
    durations = []
    for index in range(1, args.runs + 1):
        started = time.monotonic()
        try:
            result = subprocess.run(
                [str(binary), "--provider-editing-smoke"],
                capture_output=True, text=True, timeout=args.timeout,
            )
        except subprocess.TimeoutExpired as error:
            # subprocess.run kills and reaps only the child it started.
            print(json.dumps({
                "run": index, "status": "timeout", "limit": args.timeout,
                "stdout": (error.stdout or b"").decode(errors="replace"),
                "stderr": (error.stderr or b"").decode(errors="replace"),
            }), flush=True)
            return 124
        elapsed = time.monotonic() - started
        passed = (
            result.returncode == 0
            and result.stdout.splitlines().count(
                "PROVIDER_EDITING_SMOKE_PASS: native secure context Paste"
            ) == 1
            and "PROVIDER_EDITING_SMOKE_FAIL:" not in result.stdout + result.stderr
        )
        print(json.dumps({
            "run": index, "status": "pass" if passed else "fail",
            "exit": result.returncode, "seconds": round(elapsed, 3),
            "stdout": result.stdout, "stderr": result.stderr,
        }), flush=True)
        if not passed:
            return 1
        durations.append(elapsed)
    print(json.dumps({
        "passed": len(durations), "min_seconds": round(min(durations), 3),
        "max_seconds": round(max(durations), 3),
    }), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
