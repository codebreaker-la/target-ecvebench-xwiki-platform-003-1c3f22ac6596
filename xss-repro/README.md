# GHSA-36fm-j33w-c25f — XSS in XWiki XAR Import Package Explorer

## Vulnerability Summary

**Type:** Stored Cross-Site Scripting (XSS)  
**Severity:** High (admin session context)  
**Advisory:** [GHSA-36fm-j33w-c25f](https://github.com/advisories/GHSA-36fm-j33w-c25f)  
**Fix:** XWIKI-23755 (commit `cdc18aedf88`)

## Root Cause

In `import.js`, the `createPackageHeader()` function renders XAR package metadata
fields (`name`, `version`, `author`, `licence`, and the filename) using Prototype.js's
`.update()` method, which internally sets `innerHTML`. This means any HTML/JavaScript
embedded in these fields by the XAR author is executed in the browser.

**Vulnerable code** (`import.js:411-437`, before fix):
```javascript
createPackageHeader: function(infos) {
    // ...
    .insert(new Element("span", {'class':'filename'}).update(this.name))
    .insert(new Element("span", {'class':'name'}).update(infos.name))
    .insert(new Element("span", {'class':'version'}).update(infos.version))
    .insert(new Element("span", {'class':'author'}).update(infos.author))
    .insert(new Element("span", {'class':'licence'}).update(infos.licence))
    // .update() sets innerHTML — XSS!
}
```

Additionally, space names (`.update(spaceNode.reference.name)`) and document names
(`.update(displayName)`) in the package tree are also vulnerable.

On the server side, `ImportAction.java`'s `getPackageInfos()` method returns raw XAR
metadata without any HTML sanitization:
```java
XarPackage xarPackage = new XarPackage(packFile.getContentInputStream(xcontext));
xarPackage.write(response.getOutputStream(), encoding);  // raw metadata, no escaping
```

## Attack Scenario

1. Attacker crafts a XAR file with `<img src=x onerror="...">` payloads in `package.xml` metadata fields
2. Attacker distributes the XAR (e.g., as an "extension" or via social engineering)
3. XWiki admin uploads the XAR via **Administration → Content → Import**
4. Admin clicks the package name to preview its contents
5. `import.js` fetches package info via AJAX → server returns unsanitized metadata
6. `createPackageHeader()` renders fields via `.update()` → attacker JS executes
7. Attacker achieves arbitrary script execution in the admin's authenticated session

**Impact:** Full admin session hijack, arbitrary wiki content modification, user
impersonation, data exfiltration, potential remote code execution via admin-level
XWiki scripting APIs.

## How to Run the Reproduction

### Quick: Static Analysis + Malicious XAR Generation
```bash
cd xss-repro/
./run_test.sh
```

This script:
- Creates a malicious XAR file (`xss-payload.xar`) with XSS payloads in all metadata fields
- Scans `import.js` for the vulnerable `.update()` patterns on user-controlled data
- Verifies that `ImportAction.java` returns raw metadata without sanitization
- Reports which fields are vulnerable

### Browser Demo: Live XSS Proof
Open `test_xss_import.html` in any browser. It:
- Simulates the vulnerable `createPackageHeader()` function using a Prototype.js `.update()` shim
- Injects XSS payloads via simulated malicious XAR metadata
- Reports which fields successfully executed JavaScript (all 5 should fire)
- Injects visible `<b>` tags proving DOM injection (all 5 should appear)

### Full Integration Test (requires running XWiki instance)
1. Run `python3 create_malicious_xar.py` to generate `xss-payload.xar`
2. Log into XWiki as admin
3. Navigate to **Administration → Content → Import**
4. Upload `xss-payload.xar`
5. Click the uploaded package name
6. Observe: `alert()` dialogs fire from the XSS payloads in metadata fields

## Fix

The fix (commit `cdc18aedf88`, XWIKI-23755) replaces `.update(userInput)` with
`textContent` assignment:
```javascript
function makeValueSpan(className, text) {
    var span = new Element("span", {'class': className});
    span.textContent = text;  // safe: treated as text, not HTML
    return span;
}
```

## Files in This Reproduction

| File | Purpose |
|------|---------|
| `run_test.sh` | Automated reproduction script (static analysis + XAR creation) |
| `test_xss_import.html` | Browser-based live XSS demonstration |
| `create_malicious_xar.py` | Generates a malicious XAR with XSS payloads |
| `README.md` | This file |
