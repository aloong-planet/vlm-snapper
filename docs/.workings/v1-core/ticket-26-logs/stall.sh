#!/bin/bash
# Runs one test while repeatedly pausing the test process for 300 ms (SIGSTOP/SIGCONT),
# the kind of host stall a busy CI runner causes. Usage: stall.sh <filter> <log>
filter="$1"; log="$2"
/usr/bin/xcrun swift test --skip-build --filter "$filter" > "$log" 2>&1 &
runner=$!
( while kill -0 $runner 2>/dev/null; do
    for p in $(pgrep -f 'VLMSnapperPackageTests.xctest'); do kill -STOP $p 2>/dev/null; done
    sleep 0.3
    for p in $(pgrep -f 'VLMSnapperPackageTests.xctest'); do kill -CONT $p 2>/dev/null; done
    sleep 0.15
  done ) &
pauser=$!
wait $runner; code=$?
kill $pauser 2>/dev/null; for p in $(pgrep -f 'VLMSnapperPackageTests.xctest'); do kill -CONT $p 2>/dev/null; done
exit $code
