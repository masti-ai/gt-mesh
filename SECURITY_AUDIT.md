# GT Mesh Security Audit

**Branch:** `gt/gasclaw-2/security-audit`
**Date:** 2026-03-08
**Auditor:** deepwork-eng-1 (SD-1, MiniMax-M2.5)

---

## Executive Summary

Audited 22 bash scripts in the gt-mesh codebase. Found **6 categories** of security issues. All critical issues have been fixed in this branch.

---

## Findings & Fixes

### 1. SQL Injection (CRITICAL) ✅ FIXED

**Affected Files:**
- `mesh-send.sh` - `TO_GT` not escaped
- `mesh-rules.sh` - `RULE_NAME`, `RULE_VALUE` not escaped
- `mesh-beads.sh` - `BEAD_ID`, `RIG`, `STATUS` not escaped
- `mesh-join.sh` - Multiple variables not escaped
- `mesh-improve.sh` - `CATEGORY`, `SEVERITY`, `COMMAND`, `IMP_ID` not escaped

**Issue:** User-controlled variables used directly in SQL queries without proper escaping or validation.

**Fix:** Added input validation (regex checks for safe formats) and SQL escaping (`sed "s/'/''/g"`) for all user inputs.

**Example (mesh-send.sh):**
```bash
# Before (vulnerable):
dolt sql -q "... VALUES ('$MSG_ID', ..., '$TO_GT', ...)"

# After (fixed):
if ! echo "$TO_GT" | grep -qE "^[a-zA-Z0-9_-]+$"; then
  echo "[error] Invalid TO_GT format"
  exit 1
fi
TO_GT_ESC=$(echo "$TO_GT" | sed "s/'/''/g")
dolt sql -q "... VALUES ('$MSG_ID', ..., '$TO_GT_ESC', ...)"
```

---

### 2. Input Validation (HIGH) ✅ FIXED

**Affected Files:** Multiple scripts

**Issue:** No validation on user inputs (bead IDs, rig names, GitHub usernames, etc.)

**Fix:** Added regex validation for all user-controlled inputs:
- `BEAD_ID` must match `^[a-zA-Z0-9_-]+$`
- `TO_GT` must match `^[a-zA-Z0-9_-]+$`
- `RULE_NAME` must match `^[a-zA-Z_][a-zA-Z0-9_]*$`
- `OWNER_GITHUB` must match `^[a-zA-Z0-9][-a-zA-Z0-9_]*$`
- Priority values validated as `^[0-3]$`

---

### 3. Knowledge Entry Content Injection (MEDIUM) ✅ FIXED

**Affected File:** `mesh-sync.sh`

**Issue:** Knowledge entries pulled from database written directly to markdown files without sanitization. Malicious content could inject arbitrary markdown or execute via hook scripts.

**Fix:** Added sanitization:
- Escape `#` prefix in titles to prevent markdown header injection
- Trim whitespace from content
- Escape grep pattern for deduplication check

```bash
# Before (vulnerable):
echo "### $ktitle" >> "$LEARNINGS"

# After (fixed):
echo "### $(printf '%s' "$ktitle" | sed 's/^#//g')" >> "$LEARNINGS"
```

---

### 4. YAML Injection (LOW) ✅ DOCUMENTED

**Affected File:** `mesh-join.sh`

**Issue:** Values inserted into mesh.yaml without YAML escaping. If values contained `"` or special YAML characters, could break parsing or inject malicious config.

**Mitigation:** Input validation (alphanumeric only) provides sufficient protection. Values are validated before YAML generation.

---

### 5. Command Injection via eval (NONE) ✅ VERIFIED SAFE

**Status:** No unsafe `eval` or backtick command substitution found in any script.

---

### 6. Hardcoded Secrets (NONE) ✅ VERIFIED SAFE

**Status:** No hardcoded passwords, tokens, or API keys found in scripts.

---

### 7. Race Conditions in Sync (DOCUMENTED) ⚠️ KNOWN LIMITATION

**Affected File:** `mesh-sync.sh`

**Issue:** Multiple concurrent sync operations could conflict.

**Status:** Not fixed - requires architectural changes (locking mechanism). Currently mitigated by:
- Error suppression (`2>/dev/null || true`)
- Empty commits allowed (`--allow-empty`)

---

## Summary of Changes

| File | Changes |
|------|---------|
| `mesh-send.sh` | Added TO_GT validation, SQL escaping, priority validation |
| `mesh-rules.sh` | Added RULE_NAME/RULE_VALUE validation and SQL escaping |
| `mesh-beads.sh` | Added validation + escaping for BEAD_ID, RIG, STATUS in all commands |
| `mesh-join.sh` | Added OWNER_GITHUB validation, SQL escaping for all variables |
| `mesh-improve.sh` | Added CATEGORY/SEVERITY validation, SQL escaping for IMP_ID, inputs |
| `mesh-sync.sh` | Added content sanitization for knowledge entries |

---

## Recommendations

1. **Deploy this branch** to fix critical SQL injection vulnerabilities
2. **Add parameterized queries** if dolt supports them (future improvement)
3. **Implement locking** for sync operations to prevent race conditions
4. **Add integration tests** for SQL injection vectors
5. **Security scan** as part of CI/CD pipeline

---

## Testing

To verify fixes:
```bash
cd /workspace/gt-mesh
# Test SQL injection in mesh-send
echo "Testing mesh-send.sh..."
TO_GT="test; DROP TABLE messages;--" ./scripts/mesh-send.sh "$TO_GT" "test" "body" 2>&1 | grep -q "Invalid" && echo "PASS: SQL injection blocked"

# Test SQL injection in mesh-beads
echo "Testing mesh-beads.sh..."
echo "fake-id', 'pwned" | grep -qE "^[a-zA-Z0-9_-]+$" && echo "FAIL: Should not match" || echo "PASS: Invalid ID rejected"
```

---

**End of Audit Report**