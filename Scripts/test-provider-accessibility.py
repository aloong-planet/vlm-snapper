#!/usr/bin/env python3
"""Build the isolated production-view host and run coordinate-free AX regression.

Requires the separately installed, user-authorized AXRunner. Never silently skips.
No real Provider, Keychain, production app, clipboard or synthesized mouse events.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SECURE = {"AXSubrole": "AXSecureTextField"}
WINDOW = {"AXRole": "AXWindow"}


def wait(selector, attribute=None, value=None):
    step = {"op": "wait", "selector": selector, "timeout": 5}
    if attribute:
        step.update(attribute=attribute, value=value)
    return step


def button(label):
    return {"AXRole": "AXButton", "AXDescription": label}


def press(label):
    return {"op": "perform", "selector": button(label), "action": "AXPress"}


def write(value="poc-key-ax-only", selector=SECURE):
    return {"op": "set", "selector": selector, "attribute": "AXValue", "value": value}


def enabled(value):
    return wait(button("Validate"), "AXEnabled", value)


def result(title="AX fixture validated exact value 1"):
    return wait(WINDOW, "AXTitle", title)


def cases():
    yield "bilingual-descriptions", ["--history-image", "--missing-image"], [
        wait({"AXIdentifier": "bilingual-source"}, "AXDescription", "Original"),
        wait({"AXIdentifier": "bilingual-translation"}, "AXDescription", "Translation"),
    ], None
    yield "history-image-missing", ["--history-image", "--missing-image"], [
        result("AX fixture ready"), wait(button("View original image")),
    ], "step_2"
    yield "history-image", ["--history-image", "--narrow"], [
        wait(button("View original image")), press("View original image"),
        wait(button("100% actual size")), press("100% actual size"),
        wait(button("Fit to window")), press("Fit to window"),
        wait(button("100% actual size")), press("Close"),
        wait(button("View original image")), press("View original image"),
        wait(button("100% actual size")), press("Close"),
        result("AX fixture ready"),
    ], None
    submission = [wait(SECURE), write(), enabled(True), press("Validate")]
    # Negative control must reach the callback and only fail at the final effect.
    yield "drop-result", ["--drop-result"], submission + [
        result("AX fixture result dropped"), result()
    ], "step_6"
    yield "secure", [], submission + [result()], None
    for narrow in (False, True):
        for prefilled in (False, True):
            for plain in (False, True):
                arguments = (["--narrow"] if narrow else []) + (["--prefilled"] if prefilled else [])
                name = f"{'narrow' if narrow else 'wide'}-{'prefilled' if prefilled else 'empty'}-{'plain' if plain else 'secure'}"
                field = {"AXRole": "AXTextField"} if plain else SECURE
                steps = [wait(SECURE), enabled(False)]
                if plain:
                    steps += [press("Show API Key"), wait(field)]
                steps += [write(selector=field), enabled(True), press("Clear API Key"),
                          enabled(False), write(selector=field), enabled(True),
                          press("Publish fixture snapshot"), enabled(True),
                          press("Validate"), result(), enabled(False)]
                yield name, arguments, steps, None
        yield f"blocked-{'narrow' if narrow else 'wide'}", ["--blocked"] + (["--narrow"] if narrow else []), [
            wait(SECURE), write(), enabled(False), result("AX fixture ready"),
            press("Finish fixture activity"), enabled(True), press("Validate"), result()
        ], None
    for name, value in [("newline", "key\nvalue"), ("carriage-return", "key\r"),
                        ("over-limit", "x" * 4097)]:
        # Begin enabled, then invalid, then enabled again on the same button.
        # A permanently disabled or wrong control cannot make this scenario pass.
        yield name, [], [wait(SECURE), write(), enabled(True), write(value),
                         enabled(False), result("AX fixture ready"), write(),
                         enabled(True), press("Validate"), result()], None


def require(condition, report):
    # Remains a gate when Python runs with -O; assertions must not disappear.
    if not condition:
        raise RuntimeError(f"Unexpected AX report: {report}")


def run_case(runner, directory, app, name, arguments, steps, expected_failure):
    scenario = directory / f"{name}.json"
    scenario.write_text(json.dumps({
        "version": 1,
        "target": {"app": str(app), "bundleID": "com.aloong.tests.VLMSnapperAXFixture",
                   "arguments": arguments},
        "steps": steps,
    }, indent=2) + "\n")
    completed = subprocess.run(["bash", str(runner), "--scenario", str(scenario)],
                               capture_output=True, text=True, timeout=180)
    (directory / f"{name}.log").write_text(completed.stdout + completed.stderr)
    # The runner adds a human-readable path after its JSON report.
    report, _ = json.JSONDecoder().raw_decode(completed.stdout.lstrip())
    (directory / f"{name}.report.json").write_text(json.dumps(report, indent=2) + "\n")
    verify_report(report, completed.returncode, len(steps), expected_failure)
    print(f"PASS {name}" + (" (expected result assertion failure)" if expected_failure else ""), flush=True)


def verify_report(report, returncode, step_count, expected_failure):
    expected_code = 1 if expected_failure else 0
    expected_steps = step_count - (1 if expected_failure else 0)
    require(returncode == report["exitCode"] == expected_code, report)
    require(report["status"] == ("failed" if expected_failure else "passed"), report)
    require(report["reason"] == ("wait_timeout" if expected_failure else "ok"), report)
    require(report["stage"] == (expected_failure or f"step_{step_count}"), report)
    require([step["index"] for step in report["steps"]] == list(range(1, expected_steps + 1)), report)
    require(report["cleanup"] == "terminated_owned_target", report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner", type=Path,
                        default=Path.home() / "Developer/ax-test-tools/Scripts/run.sh")
    parser.add_argument("--case", help="Run one named case (still rebuilds the fixture)")
    options = parser.parse_args()
    selected = [case for case in cases() if not options.case or case[0] == options.case]
    if not selected:
        parser.error("Unknown case")
    if not options.runner.is_file():
        parser.error("Install and authorize AXRunner first; missing runner is not a pass")
    directory = Path(tempfile.mkdtemp(prefix="vlmsnapper-ax-regression-"))
    print(f"Evidence: {directory}", flush=True)
    env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
    with (directory / "build.log").open("w") as log:
        subprocess.run(["swift", "build", "--product", "VLMSnapperAXFixture",
                        "-Xswiftc", "-warnings-as-errors"], cwd=ROOT, env=env,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    binary_dir = Path(subprocess.check_output(["swift", "build", "--show-bin-path"],
                                             cwd=ROOT, env=env, text=True).strip())
    app = directory / "VLMSnapperAXFixture.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    shutil.copy2(binary_dir / "VLMSnapperAXFixture", app / "Contents/MacOS/VLMSnapperAXFixture")
    shutil.copy2(ROOT / "Tests/AXFixture/Info.plist", app / "Contents/Info.plist")
    shutil.copytree(binary_dir / "VLMSnapper_VLMSnapperUI.bundle",
                    app / "Contents/Resources/VLMSnapper_VLMSnapperUI.bundle")
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    for name, arguments, steps, expected_failure in selected:
        run_case(options.runner.resolve(), directory, app, name, arguments, steps, expected_failure)
    print(f"AX regression: {len(selected)} cases passed; evidence: {directory}")


if __name__ == "__main__":
    main()
