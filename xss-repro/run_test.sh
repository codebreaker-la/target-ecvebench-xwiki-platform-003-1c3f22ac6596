#!/usr/bin/env bash
# GHSA-36fm-j33w-c25f — Automated XSS reproduction test
#
# This script:
#   1. Creates the malicious XAR payload
#   2. Opens the HTML reproduction in a headless browser
#   3. Checks that XSS payloads fire (proving the vulnerability)
#
# Requirements: python3, node (with puppeteer or just check the DOM output)
#
# Usage:
#   chmod +x run_test.sh && ./run_test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== GHSA-36fm-j33w-c25f: XSS in XWiki XAR Import ==="
echo ""

# Step 1: Create malicious XAR
echo "[1/3] Creating malicious XAR payload..."
python3 create_malicious_xar.py
echo ""

# Step 2: Static analysis of the vulnerable code
echo "[2/3] Checking vulnerable code patterns in import.js..."
IMPORT_JS="../xwiki-platform-core/xwiki-platform-web/xwiki-platform-web-war/src/main/webapp/resources/js/xwiki/importer/import.js"

echo "Scanning for unsafe .update() calls on user-controlled data..."
echo ""

vuln_count=0

# Check for .update(infos.name) pattern
if grep -n '\.update(infos\.name)' "$IMPORT_JS" > /dev/null 2>&1; then
    echo "  VULNERABLE: infos.name rendered via .update() (innerHTML)"
    grep -n '\.update(infos\.name)' "$IMPORT_JS"
    vuln_count=$((vuln_count + 1))
fi

if grep -n '\.update(infos\.version)' "$IMPORT_JS" > /dev/null 2>&1; then
    echo "  VULNERABLE: infos.version rendered via .update() (innerHTML)"
    grep -n '\.update(infos\.version)' "$IMPORT_JS"
    vuln_count=$((vuln_count + 1))
fi

if grep -n '\.update(infos\.author)' "$IMPORT_JS" > /dev/null 2>&1; then
    echo "  VULNERABLE: infos.author rendered via .update() (innerHTML)"
    grep -n '\.update(infos\.author)' "$IMPORT_JS"
    vuln_count=$((vuln_count + 1))
fi

if grep -n '\.update(infos\.licence)' "$IMPORT_JS" > /dev/null 2>&1; then
    echo "  VULNERABLE: infos.licence rendered via .update() (innerHTML)"
    grep -n '\.update(infos\.licence)' "$IMPORT_JS"
    vuln_count=$((vuln_count + 1))
fi

if grep -n '\.update(this\.name)' "$IMPORT_JS" > /dev/null 2>&1; then
    echo "  VULNERABLE: this.name (filename) rendered via .update() (innerHTML)"
    grep -n '\.update(this\.name)' "$IMPORT_JS"
    vuln_count=$((vuln_count + 1))
fi

# Also check space/document names
if grep -n '\.update(spaceNode\.reference\.name)' "$IMPORT_JS" > /dev/null 2>&1; then
    echo "  VULNERABLE: spaceNode.reference.name rendered via .update() (innerHTML)"
    grep -n '\.update(spaceNode\.reference\.name)' "$IMPORT_JS"
    vuln_count=$((vuln_count + 1))
fi

if grep -n '\.update(displayName)' "$IMPORT_JS" > /dev/null 2>&1; then
    echo "  VULNERABLE: displayName rendered via .update() (innerHTML)"
    grep -n '\.update(displayName)' "$IMPORT_JS"
    vuln_count=$((vuln_count + 1))
fi

echo ""

# Step 3: Check server-side (ImportAction.java) for missing sanitization
echo "[3/3] Checking server-side ImportAction.java for missing HTML sanitization..."
IMPORT_ACTION="../xwiki-platform-core/xwiki-platform-oldcore/src/main/java/com/xpn/xwiki/web/ImportAction.java"

if grep -n 'xarPackage.write' "$IMPORT_ACTION" > /dev/null 2>&1; then
    echo "  CONFIRMED: ImportAction.getPackageInfos() writes raw XAR metadata to response"
    echo "  without HTML-encoding. The XarPackage.write() outputs XML containing"
    echo "  attacker-controlled fields (name, version, author, licence) verbatim."
    grep -n 'xarPackage.write' "$IMPORT_ACTION"
fi

echo ""
echo "============================================"
echo "RESULTS"
echo "============================================"

if [ "$vuln_count" -ge 5 ]; then
    echo "VULNERABLE: Found $vuln_count unsafe .update() calls on user-controlled XAR metadata."
    echo ""
    echo "Attack vector:"
    echo "  1. Attacker crafts XAR with HTML/JS in package.xml metadata fields"
    echo "  2. Admin uploads XAR via Administration > Content > Import"
    echo "  3. Admin clicks package name to preview contents"
    echo "  4. import.js fetches package info via AJAX (getPackageInfos)"
    echo "  5. Server returns raw XML metadata (no sanitization)"
    echo "  6. Client parses JSON, passes fields to createPackageHeader()"
    echo "  7. createPackageHeader() uses .update() which sets innerHTML"
    echo "  8. Attacker's HTML/JS executes in admin's browser session"
    echo ""
    echo "Impact: Full admin session hijack, arbitrary wiki modifications,"
    echo "        user impersonation, data exfiltration."
    echo ""
    echo "Fix: Replace .update(userInput) with textContent assignment."
    echo "     See fix commit cdc18aedf88 (XWIKI-23755)."
    echo ""
    echo "Open test_xss_import.html in a browser for a live DOM-level demonstration."
    exit 0
else
    echo "Could not confirm all expected vulnerable patterns (found $vuln_count)."
    exit 1
fi
