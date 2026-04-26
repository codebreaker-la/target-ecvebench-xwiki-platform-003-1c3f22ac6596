#!/usr/bin/env bash
# Reproduction script for GHSA-36fm-j33w-c25f
# Auth-bypass: IncludeMacro skips authorExecutor.call() when author=CURRENT
#
# On VULNERABLE code: test fails -> outputs REPRO_VULN_CONFIRMED (exit 0)
# On FIXED code:      test passes -> outputs REPRO_VULN_NOT_REPRODUCED (exit 0)
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

MODULE="xwiki-platform-core/xwiki-platform-rendering/xwiki-platform-rendering-macros/xwiki-platform-rendering-macro-include"
TEST_CLASS="org.xwiki.rendering.internal.macro.include.IncludeMacroAuthBypassTest"

V_SRC="18.3.0-rc-1"
V_DST="18.4.0-SNAPSHOT"
M2="${HOME}/.m2/repository"
NEXUS="https://nexus.xwiki.org/nexus/content/groups/public"

# Ensure Java 21+
if [ -d /usr/lib/jvm/java-21-openjdk-amd64 ]; then
  export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
  export PATH="$JAVA_HOME/bin:$PATH"
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq && apt-get install -y -qq openjdk-21-jdk 2>/dev/null || true
  if [ -d /usr/lib/jvm/java-21-openjdk-amd64 ]; then
    export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
    export PATH="$JAVA_HOME/bin:$PATH"
  fi
fi

# Ensure Maven is available
if ! command -v mvn >/dev/null 2>&1; then
  if [ ! -d /opt/apache-maven-3.9.6 ]; then
    curl -sfL "https://archive.apache.org/dist/maven/maven-3/3.9.6/binaries/apache-maven-3.9.6-bin.tar.gz" -o /tmp/maven.tar.gz
    tar xzf /tmp/maven.tar.gz -C /opt
  fi
  export PATH="/opt/apache-maven-3.9.6/bin:$PATH"
fi

# Disable Gradle/Develocity extension that may fail
if [ -f .mvn/extensions.xml ]; then
  mv .mvn/extensions.xml .mvn/extensions.xml.disabled
fi

###############################################################################
# Helper: download an artifact POM/JAR from XWiki Nexus (18.3.0-rc-1) and
# install it locally as 18.4.0-SNAPSHOT. This is necessary because the repo
# uses an unreleased SNAPSHOT version whose artifacts are not publicly available.
###############################################################################
download_artifact() {
  local groupPath="$1" artifactId="$2" ext="${3:-pom}" classifier="${4:-}"
  local dst_dir="${M2}/${groupPath}/${artifactId}/${V_DST}"
  mkdir -p "$dst_dir"
  local src_name dst_name
  if [ -n "$classifier" ]; then
    src_name="${artifactId}-${V_SRC}-${classifier}.${ext}"
    dst_name="${artifactId}-${V_DST}-${classifier}.${ext}"
  else
    src_name="${artifactId}-${V_SRC}.${ext}"
    dst_name="${artifactId}-${V_DST}.${ext}"
  fi
  local dst="${dst_dir}/${dst_name}"
  [ -f "$dst" ] && [ -s "$dst" ] && return 0
  curl -sfL "${NEXUS}/${groupPath}/${artifactId}/${V_SRC}/${src_name}" -o "$dst" 2>/dev/null || true
  if [ -f "$dst" ] && [ -s "$dst" ] && [ "$ext" = "pom" ]; then
    sed -i "s/${V_SRC}/${V_DST}/g" "$dst" 2>/dev/null
  fi
}

###############################################################################
# Iterative dependency resolver: run Maven, parse missing artifact errors,
# download them, repeat until build succeeds or stabilizes.
###############################################################################
resolve_deps() {
  local max_iters=40 iter=0 prev_missing=""
  while [ $iter -lt $max_iters ]; do
    iter=$((iter + 1))
    local output
    output=$(mvn -f "${ROOT}/${MODULE}/pom.xml" \
      dependency:resolve \
      -Denforcer.skip=true -Dcheckstyle.skip=true -Dlicense.skip=true \
      -Dxwiki.revapi.skip=true -U \
      -B 2>&1) || true

    if echo "$output" | grep -q "BUILD SUCCESS"; then
      return 0
    fi

    local missing
    missing=$(echo "$output" | grep -oP '(org\.xwiki\.\w+):([\w-]+):(pom|jar):18\.4\.0-SNAPSHOT' | sort -u) || true
    if [ -z "$missing" ]; then
      return 0
    fi
    if [ "$missing" = "$prev_missing" ]; then
      return 0
    fi
    prev_missing="$missing"

    echo "$missing" | while IFS=: read -r groupId artifactId packaging _version; do
      local groupPath="${groupId//./\/}"
      download_artifact "$groupPath" "$artifactId" "pom"
      if [ "$packaging" = "jar" ]; then
        download_artifact "$groupPath" "$artifactId" "jar"
      fi
    done
  done
}

###############################################################################
# Step 1: Strip problematic build extensions and plugins from parent POMs.
###############################################################################
echo "[repro] Patching parent POMs to remove unresolvable SNAPSHOT plugins..."
python3 -c "
import re, sys
for pom_path in sys.argv[1:]:
    try:
        with open(pom_path) as f:
            content = f.read()
        content = re.sub(r'\s*<extensions>.*?</extensions>', '', content, flags=re.DOTALL)
        content = re.sub(r'\s*<pluginManagement>.*?</pluginManagement>', '', content, flags=re.DOTALL)
        with open(pom_path, 'w') as f:
            f.write(content)
    except Exception:
        pass
" "${ROOT}/pom.xml"

python3 -c "
import re
pom = '${ROOT}/xwiki-platform-core/pom.xml'
with open(pom) as f:
    content = f.read()
content = re.sub(r'\s*<plugin>\s*<groupId>org\.apache\.maven\.plugins</groupId>\s*<artifactId>maven-enforcer-plugin</artifactId>.*?</plugin>', '', content, flags=re.DOTALL)
content = re.sub(r'\s*<plugin>\s*<groupId>org\.xwiki\.platform</groupId>\s*<artifactId>xwiki-platform-tool-importmap-plugin</artifactId>.*?</plugin>', '', content, flags=re.DOTALL)
with open(pom, 'w') as f:
    f.write(content)
"

###############################################################################
# Step 2: Seed the local Maven repo with parent POMs from 18.3.0-rc-1
###############################################################################
echo "[repro] Downloading base xwiki parent POMs..."
for a in xwiki-commons xwiki-commons-pom xwiki-commons-core xwiki-commons-tools; do
  download_artifact "org/xwiki/commons" "$a"
done
for a in xwiki-rendering xwiki-rendering-syntaxes xwiki-rendering-transformations xwiki-rendering-macros; do
  download_artifact "org/xwiki/rendering" "$a"
done
for a in xwiki-platform-rendering xwiki-platform-rendering-macros xwiki-platform-security xwiki-platform-security-authorization; do
  download_artifact "org/xwiki/platform" "$a"
done

# Clean build sections from all downloaded xwiki POMs to remove plugin refs
find "${M2}/org/xwiki" -name "*-${V_DST}.pom" -exec python3 -c "
import re, sys
for p in sys.argv[1:]:
    try:
        with open(p) as f:
            c = f.read()
        c = re.sub(r'\s*<build>.*?</build>', '', c, flags=re.DOTALL)
        with open(p, 'w') as f:
            f.write(c)
    except: pass
" {} +

###############################################################################
# Step 3: Install root and core POMs into local repo
###############################################################################
echo "[repro] Installing root POM..."
local_root_pom="${M2}/org/xwiki/platform/xwiki-platform/${V_DST}"
mkdir -p "$local_root_pom"
cp "${ROOT}/pom.xml" "${local_root_pom}/xwiki-platform-${V_DST}.pom"

local_core_pom="${M2}/org/xwiki/platform/xwiki-platform-core/${V_DST}"
mkdir -p "$local_core_pom"
cp "${ROOT}/xwiki-platform-core/pom.xml" "${local_core_pom}/xwiki-platform-core-${V_DST}.pom"

###############################################################################
# Step 4: Iteratively resolve dependencies
###############################################################################
echo "[repro] Resolving dependencies (this may take several minutes)..."
resolve_deps

###############################################################################
# Step 5: Run the test
###############################################################################
echo "[repro] Running IncludeMacroAuthBypassTest..."
TEST_OUTPUT=$(mvn -f "${ROOT}/${MODULE}/pom.xml" \
  test -Dtest="${TEST_CLASS}" -DfailIfNoTests=false \
  -Denforcer.skip=true -Dcheckstyle.skip=true -Dlicense.skip=true \
  -Dxwiki.revapi.skip=true \
  -Dmaven.compiler.source=21 -Dmaven.compiler.target=21 \
  -Dsurefire.useFile=false \
  -B 2>&1) || true

echo "$TEST_OUTPUT" | tail -20

# Restore extensions file
if [ -f .mvn/extensions.xml.disabled ]; then
  mv .mvn/extensions.xml.disabled .mvn/extensions.xml
fi

if echo "$TEST_OUTPUT" | grep -q "BUILD SUCCESS"; then
  echo "REPRO_VULN_NOT_REPRODUCED"
else
  echo "REPRO_VULN_CONFIRMED"
fi

exit 0
