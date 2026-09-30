#!/usr/bin/env bash
# dpkg command double: exercise identity gates without building/installing packages.
set -euo pipefail
umask 077 # The package verifier requires a private work directory.
root="$(cd "$(dirname "$0")/.." && pwd)"
t="$(mktemp -d)"
trap 'find "$t" -depth -delete' EXIT
mkdir "$t/bin" "$t/work"
printf 'CONFIG_FIXTURE=y\n' > "$t/config"
printf fixture-image > "$t/image"
printf fixture-package > "$t/pkg.deb"
cat > "$t/bin/dpkg-deb" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == -f ]]; then echo "linux-image-${PACKAGE_RELEASE:-6.18.53-fixture}"; exit; fi
mkdir -p "$3/boot"
cp "$FIXTURE_CONFIG" "$3/boot/config-6.18.53-fixture"
cp "$FIXTURE_IMAGE" "$3/boot/vmlinuz-6.18.53-fixture"
[[ "${CORRUPT_CONFIG:-0}" == 0 ]] || echo corrupt >> "$3/boot/config-6.18.53-fixture"
[[ "${CORRUPT_IMAGE:-0}" == 0 ]] || echo corrupt >> "$3/boot/vmlinuz-6.18.53-fixture"
EOF
chmod +x "$t/bin/dpkg-deb"
export PATH="$t/bin:$PATH" FIXTURE_CONFIG="$t/config" FIXTURE_IMAGE="$t/image"
run() { bash "$root/scripts/verify-build-packages.sh" 6.18.53-fixture "$t/config" "$t/image" "$t/work" "$t/pkg.deb"; }
run
if PACKAGE_RELEASE=wrong run; then exit 1; fi
if CORRUPT_CONFIG=1 run; then exit 1; fi
if CORRUPT_IMAGE=1 run; then exit 1; fi
echo 'PASS package config/image/release identity fixtures'
