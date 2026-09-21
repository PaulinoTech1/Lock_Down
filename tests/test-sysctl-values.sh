#!/usr/bin/env bash
# tests/test-sysctl-values.sh - Validate sysctl/99-workstation-hardening.conf.
#
# Checks: the file parses (every non-comment, non-blank line is key=value),
# no duplicate keys, no trailing whitespace on assignment lines, and keys
# use the expected dotted sysctl namespace shape.
# Pure file parsing; safe in CI. Never touches live sysctl state.
#
# LOCAL-safe: reads repo files only.

set -euo pipefail

CONF="${1:-sysctl/99-workstation-hardening.conf}"

if [[ ! -f "${CONF}" ]]; then
    echo "FAIL: sysctl config not found: ${CONF}" >&2
    exit 1
fi

fail=0
declare -A seen
lineno=0

while IFS= read -r line || [[ -n "${line}" ]]; do
    lineno=$((lineno + 1))
    # Strip leading whitespace for classification.
    stripped="$(echo "${line}" | sed 's/^[[:space:]]*//')"
    # Skip blanks and comments (including indented comments).
    if [[ -z "${stripped}" || "${stripped}" == \#* ]]; then
        continue
    fi
    # Must be key=value with exactly one '=' separating key and value.
    if [[ "${stripped}" != *=* ]]; then
        echo "FAIL: line ${lineno}: not a key=value assignment: ${stripped}" >&2
        fail=1
        continue
    fi
    key="${stripped%%=*}"
    value="${stripped#*=}"
    # Key shape: dotted namespace, no spaces.
    if [[ ! "${key}" =~ ^[a-z0-9_]+(\.[a-z0-9_]+)+$ ]]; then
        echo "FAIL: line ${lineno}: malformed key '${key}'" >&2
        fail=1
        continue
    fi
    if [[ -z "${value}" ]]; then
        echo "FAIL: line ${lineno}: empty value for key '${key}'" >&2
        fail=1
        continue
    fi
    # Trailing whitespace check on the raw line.
    if [[ "${line}" =~ [[:space:]]$ ]]; then
        echo "FAIL: line ${lineno}: trailing whitespace" >&2
        fail=1
    fi
    # Duplicate key check.
    if [[ -n "${seen[${key}]:-}" ]]; then
        echo "FAIL: line ${lineno}: duplicate key '${key}' (first at line ${seen[${key}]})" >&2
        fail=1
    else
        seen["${key}"]="${lineno}"
    fi
done < "${CONF}"

if [[ "${fail}" -ne 0 ]]; then
    echo "test-sysctl-values: FAILED" >&2
    exit 1
fi
echo "test-sysctl-values: PASS (${#seen[@]} keys, no dupes, all parse)"
