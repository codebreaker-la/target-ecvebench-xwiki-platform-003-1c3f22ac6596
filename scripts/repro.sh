#!/usr/bin/env bash
# GHSA-36fm-j33w-c25f reproduction script
# Runs the unit test that verifies authorExecutor.call() is invoked for Author.CURRENT.
# Vulnerable code: test FAILS  → prints REPRO_VULN_CONFIRMED
# Fixed code:      test PASSES → prints REPRO_VULN_NOT_REPRODUCED

cd "$(dirname "$0")/.."

mvn test \
  -pl xwiki-platform-core/xwiki-platform-rendering/xwiki-platform-rendering-macros/xwiki-platform-rendering-macro-include \
  -Dtest="IncludeMacroTest#executeWithCURRENTAuthorShouldCallAuthorExecutor" \
  -DfailIfNoTests=false \
  -am -q 2>&1
TEST_EXIT=$?

if [ "$TEST_EXIT" -ne 0 ]; then
  echo "REPRO_VULN_CONFIRMED"
  exit 0
else
  echo "REPRO_VULN_NOT_REPRODUCED"
  exit 0
fi
