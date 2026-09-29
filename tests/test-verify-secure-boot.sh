#!/usr/bin/env bash
# Command fixtures only; never query the host's boot state.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"
trap 'find "$t" -depth -delete' EXIT
mkdir -p "$t/bin" "$t/proc" "$t/sys/kernel/security" "$t/boot"
cat > "$t/bin/uname" <<'EOF'
#!/usr/bin/env bash
echo fixture-release
EOF
cat > "$t/bin/mokutil" <<'EOF'
#!/usr/bin/env bash
case "$SB" in missing) exit 127;; unknown) echo nonsense;; *) echo "SecureBoot $SB";; esac
EOF
cat > "$t/bin/dmesg" <<'EOF'
#!/usr/bin/env bash
echo 'secure boot disabled: historical fixture line'
EOF
chmod +x "$t/bin/"*
export PATH="$t/bin:$PATH" BOOT_EVIDENCE_ROOT="$t" EXPECTED_KERNEL=fixture-release SB=enabled
printf 'none [integrity] confidentiality\n' > "$t/sys/kernel/security/lockdown"
printf '# CONFIG_MODULES is not set\n' > "$t/boot/config-fixture-release"
check() {
    local expected="$1" label="$2" rc=0
    bash "$root/scripts/verify-secure-boot.sh" > "$t/log" 2>&1 || rc=$?
    if [[ "$rc" != "$expected" ]]; then cat "$t/log"; echo "FAIL $label: exit $rc expected $expected"; exit 1; fi
    echo "PASS $label"
}
check 0 'enabled matching monolithic'
grep -q 'NOT_APPLICABLE.*module' "$t/log"
! grep -q 'PASS.*historical fixture' "$t/log"
EXPECTED_KERNEL=wrong check 1 'release mismatch'
SB=disabled check 1 'disabled Secure Boot'
SB=unknown check 3 'unparseable evidence'
SB=missing check 3 'unavailable mokutil'
printf 'CONFIG_MODULES=y\n' > "$t/boot/config-fixture-release"
check 1 'modular without enforcement'
printf 'CONFIG_MODULE_SIG_FORCE=y\n' >> "$t/boot/config-fixture-release"
check 0 'modular with force policy'
rm -- "$t/boot/config-fixture-release"
check 3 'unreadable config'
EXPECTED_KERNEL=wrong check 1 'FAIL outranks UNKNOWN'
printf '# CONFIG_MODULES is not set\n' > "$t/boot/config-fixture-release"
rm -- "$t/sys/kernel/security/lockdown"
check 3 'missing lockdown'
echo 'PASS secure boot fixture suite'
