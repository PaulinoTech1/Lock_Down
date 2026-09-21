#!/usr/bin/env bash
# audit-pam-u2f.sh: read-only auditor for pam_u2f deployment.
#
# Purpose: verify the YubiKey PAM policy from docs/YUBIKEY_PAM.md is in
# place, without changing anything. All output is PASS/WARN/FAIL/UNKNOWN
# per check. Never reports PASS for a state it cannot verify.
#
# Usage: ./audit-pam-u2f.sh
# Exit: 0 if no FAIL, 1 if any FAIL.
#
# Read-only: makes no writes, starts no services, touches no auth state.

set -euo pipefail

SERVICES=(sudo login sddm)
MAPPING_FILE="/etc/u2f_mappings"
MODULE_CANDIDATES=(
    "/usr/lib/x86_64-linux-gnu/security/pam_u2f.so"
    "/lib/x86_64-linux-gnu/security/pam_u2f.so"
    "/usr/lib/security/pam_u2f.so"
)

fail_count=0

report() {
    local level="$1" check="$2" detail="$3"
    printf '%s\t%s\t%s\n' "$level" "$check" "$detail"
    if [ "$level" = "FAIL" ]; then
        fail_count=$((fail_count + 1))
    fi
}

# ---------------------------------------------------------------- module ---
module_path=""
for candidate in "${MODULE_CANDIDATES[@]}"; do
    if [ -f "$candidate" ]; then
        module_path="$candidate"
        break
    fi
done

if [ -n "$module_path" ]; then
    report "PASS" "pam_u2f-module-installed" "found at $module_path"
else
    report "FAIL" "pam_u2f-module-installed" \
        "pam_u2f.so not found in any known module path (libpam-u2f missing?)"
fi

# -------------------------------------------------------------- mapping ----
if [ -f "$MAPPING_FILE" ]; then
    owner="$(stat -c '%U:%G' "$MAPPING_FILE")"
    mode="$(stat -c '%a' "$MAPPING_FILE")"
    if [ "$owner" = "root:root" ] && [ "$mode" = "600" ]; then
        report "PASS" "u2f-mapping-permissions" \
            "$MAPPING_FILE is root:root mode 600"
    else
        report "FAIL" "u2f-mapping-permissions" \
            "$MAPPING_FILE is $owner mode $mode (want root:root 600)"
    fi
    if [ -s "$MAPPING_FILE" ]; then
        line_count="$(wc -l < "$MAPPING_FILE" | tr -d ' ')"
        report "PASS" "u2f-mapping-nonempty" \
            "$MAPPING_FILE has $line_count line(s)"
    else
        report "FAIL" "u2f-mapping-nonempty" "$MAPPING_FILE is empty"
    fi
else
    report "FAIL" "u2f-mapping-exists" "$MAPPING_FILE does not exist"
fi

# -------------------------------------------------------------- services ---
for service in "${SERVICES[@]}"; do
    pam_file="/etc/pam.d/$service"
    tag="pam-u2f-$service"

    if [ ! -f "$pam_file" ]; then
        report "UNKNOWN" "$tag" "$pam_file does not exist on this machine"
        continue
    fi

    # Only consider active (non-comment) auth lines mentioning pam_u2f.
    u2f_lines="$(grep -v '^[[:space:]]*#' "$pam_file" \
        | grep -E '^[[:space:]]*auth[[:space:]].*pam_u2f\.so' || true)"

    if [ -z "$u2f_lines" ]; then
        report "WARN" "$tag" "$pam_file has no active pam_u2f auth line"
        continue
    fi

    report "PASS" "$tag" "$pam_file references pam_u2f.so"

    while IFS= read -r line; do
        if printf '%s\n' "$line" | grep -qw "nouserok"; then
            report "FAIL" "$tag-nouserok" \
                "nouserok present in $pam_file: unmapped users bypass the key"
        fi
        if printf '%s\n' "$line" | grep -qE '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]'; then
            report "FAIL" "$tag-sufficient-ordering" \
                "'sufficient' pam_u2f line in $pam_file weakens the two-factor AND"
        fi
        if ! printf '%s\n' "$line" | grep -qE '^[[:space:]]*auth[[:space:]]+required[[:space:]]'; then
            report "WARN" "$tag-control-flag" \
                "pam_u2f line in $pam_file is not 'required': $line"
        fi
        if ! printf '%s\n' "$line" | grep -qw "userpresence"; then
            report "WARN" "$tag-userpresence" \
                "userpresence (touch) not requested in $pam_file"
        fi
    done <<< "$u2f_lines"

    # pam_unix should also be required so password stays mandatory.
    if grep -v '^[[:space:]]*#' "$pam_file" \
        | grep -qE '^[[:space:]]*auth[[:space:]]+required[[:space:]]+.*pam_unix\.so'; then
        report "PASS" "$tag-password-required" \
            "$pam_file keeps pam_unix as required"
    else
        report "WARN" "$tag-password-required" \
            "no 'auth required pam_unix.so' line found in $pam_file"
    fi
done

# ------------------------------------------------- screen locker coverage ---
# The locker service name varies by KDE version; report what is verifiable.
locker_found="no"
for candidate in kde sddm; do
    if [ -f "/etc/pam.d/$candidate" ]; then
        locker_found="yes"
        break
    fi
done
if [ "$locker_found" = "yes" ]; then
    report "PASS" "screen-locker-pam-present" \
        "candidate locker PAM file exists (verify it carries pam_u2f by hand)"
else
    report "UNKNOWN" "screen-locker-pam-present" \
        "no known locker PAM file found; verify the installed locker's service name"
fi

# --------------------------------------------------------------- summary ---
if [ "$fail_count" -gt 0 ]; then
    printf 'RESULT: FAIL (%d failing check(s))\n' "$fail_count" >&2
    exit 1
fi
printf 'RESULT: OK (no FAIL; review WARN/UNKNOWN lines)\n'
exit 0
