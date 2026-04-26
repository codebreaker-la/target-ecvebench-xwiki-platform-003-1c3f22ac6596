#!/usr/bin/env bash
# Reproduction script for GHSA-36fm-j33w-c25f
# Exit-code convention (for the *vulnerable* branch):
#   test FAILS  → vulnerability present → print REPRO_VULN_CONFIRMED   (exit 0)
#   test PASSES → vulnerability absent  → print REPRO_VULN_NOT_REPRODUCED (exit 1)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# Ensure JAVA_HOME points to Java 21+ if available
if [ -d /usr/lib/jvm/java-21-openjdk-amd64 ]; then
    export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
fi

# Run only the auth-bypass regression test
mvn -pl xwiki-platform-core/xwiki-platform-rendering/xwiki-platform-rendering-macros/xwiki-platform-rendering-macro-include \
    -am test \
    -Dtest=IncludeMacroAuthBypassTest \
    -Dsurefire.failIfNoSpecifiedTests=false \
    -DfailIfNoTests=false \
    -Psnapshot \
    -B 2>&1 | tail -40
TEST_EXIT=${PIPESTATUS[0]}

if [ "$TEST_EXIT" -ne 0 ]; then
    echo "REPRO_VULN_CONFIRMED"
    exit 0
else
    echo "REPRO_VULN_NOT_REPRODUCED"
    exit 1
fi
