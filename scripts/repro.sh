#!/usr/bin/env bash
# GHSA-36fm-j33w-c25f reproduction script
# Runs a single unit test that verifies authorExecutor.call() is invoked
# when author=CURRENT and context=CURRENT in the IncludeMacro.
#
# On VULNERABLE code: the test FAILS (authorExecutor.call not invoked)
#   -> script prints REPRO_VULN_CONFIRMED
# On FIXED code: the test PASSES (authorExecutor.call IS invoked)
#   -> script prints REPRO_VULN_NOT_REPRODUCED

set -uo pipefail

# Ensure Java 21+ is used
if [ -d /usr/lib/jvm/java-21-openjdk-amd64 ]; then
  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
  export PATH="$JAVA_HOME/bin:$PATH"
fi

# Disable Gradle/Develocity extension that may fail without network
if [ -f .mvn/extensions.xml ]; then
  mv .mvn/extensions.xml .mvn/extensions.xml.disabled
fi

MODULE="xwiki-platform-core/xwiki-platform-rendering/xwiki-platform-rendering-macros/xwiki-platform-rendering-macro-include"
TEST_CLASS="org.xwiki.rendering.internal.macro.include.IncludeMacroTest"
TEST_METHOD="executeWithCURRENTAuthorShouldCallAuthorExecutor"

mvn test \
  -pl "${MODULE}" \
  -Dtest="${TEST_CLASS}#${TEST_METHOD}" \
  -Dsurefire.useFile=false \
  -DfailIfNoTests=false \
  -Denforcer.skip=true \
  -Drevapi.skip=true \
  --batch-mode 2>&1 | tail -80
TEST_EXIT=${PIPESTATUS[0]}

# Restore extensions file
if [ -f .mvn/extensions.xml.disabled ]; then
  mv .mvn/extensions.xml.disabled .mvn/extensions.xml
fi

if [ "${TEST_EXIT}" -ne 0 ]; then
  echo "REPRO_VULN_CONFIRMED"
else
  echo "REPRO_VULN_NOT_REPRODUCED"
fi

exit 0
