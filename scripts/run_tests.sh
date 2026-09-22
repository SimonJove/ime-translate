#!/bin/bash
# Run every headless unit test; non-zero exit if any fails.
set -u
cd "$(dirname "$0")/.."
fail=0
for f in tests/test_*.lua; do
  if lua "$f"; then echo "PASS $f"; else echo "FAIL $f"; fail=1; fi
done
exit $fail
