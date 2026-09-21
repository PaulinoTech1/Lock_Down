#!/usr/bin/env bash
#
# build-kernel.sh -- safe custom-kernel build workflow for the
# thinkpad-hardened-workstation project.
#
# What it does:
#   1. Checks for required build tools.
#   2. Downloads the documented 6.18.x tarball over HTTPS from kernel.org
#      (with .sign signature verification guidance; never curl|sh).
#   3. Applies repo/config/hardened.config (or diagnostic.config) via
#      scripts/kconfig/merge_config.sh on top of the running distro config.
#   4. Signs modules if a project key exists; skips cleanly with a warning
#      if not (unsigned modules will then fail under MODULE_SIG_FORCE).
#   5. Builds .deb packages via make deb-pkg.
#   6. NEVER removes existing kernels. The distro rescue kernel and old
#      working custom kernels stay installed.
#
# Usage:
#   ./repo/scripts/build-kernel.sh [--profile hardened|diagnostic] [--dry-run]
#
# Next steps after a successful build are printed at the end.
#
# FIRST PASS script: review before running on the target machine.

set -euo pipefail

# --- Defaults (overridable via flags) ---
PROFILE="hardened"
DRY_RUN=0

# Kernel branch under test. The x.y.z below is an EXAMPLE to be re-checked
# against https://kernel.org at build time; it is not pinned truth.
# See repo/docs/KERNEL_VERSION_POLICY.md for the re-verify requirement.
KVERSION_MAJOR="6.18"
KVERSION_EXAMPLE="6.18.3"
KERNEL_BASE_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/repo/config"
WORK_DIR="${REPO_ROOT}/repo/build"

log()  { printf '[build-kernel] %s\n' "$*"; }
warn() { printf '[build-kernel] WARNING: %s\n' "$*" >&2; }
die()  { printf '[build-kernel] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: build-kernel.sh [--profile hardened|diagnostic] [--dry-run]

  --profile hardened|diagnostic   Which config fragment to apply (default: hardened).
  --dry-run                      Print what would be done; change nothing.
EOF
}

# --- Flag parsing ---
while [ $# -gt 0 ]; do
    case "$1" in
        --profile)
            PROFILE="${2:?--profile requires an argument}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1 (see --help)"
            ;;
    esac
done

[ "${PROFILE}" = "hardened" ] || [ "${PROFILE}" = "diagnostic" ] || \
    die "profile must be 'hardened' or 'diagnostic', got '${PROFILE}'"

FRAGMENT="${CONFIG_DIR}/${PROFILE}.config"
[ -f "${FRAGMENT}" ] || die "config fragment not found: ${FRAGMENT}"

TARBALL="linux-${KVERSION_EXAMPLE}.tar.xz"
TARBALL_URL="${KERNEL_BASE_URL}/${TARBALL}"
SIGN_URL="${TARBALL_URL}.sign"
SRC_DIR="${WORK_DIR}/linux-${KVERSION_EXAMPLE}"

run() {
    if [ "${DRY_RUN}" -eq 1 ]; then
        printf '[dry-run] %s\n' "$*"
    else
        "$@"
    fi
}

# --- 1. Required commands ---
log "Checking required build tools..."
REQUIRED_CMDS="make gcc flex bison openssl"
MISSING=""
for cmd in ${REQUIRED_CMDS}; do
    command -v "${cmd}" >/dev/null 2>&1 || MISSING="${MISSING} ${cmd}"
done
# pahole is required for the diagnostic profile (BTF); advisory otherwise.
if [ "${PROFILE}" = "diagnostic" ]; then
    command -v pahole >/dev/null 2>&1 || MISSING="${MISSING} pahole"
fi
if [ -n "${MISSING}" ]; then
    die "missing required commands:${MISSING}. Install build deps first, e.g.: sudo apt install build-essential flex bison libssl-dev pahole libelf-dev"
fi
# libssl-dev presence check (headers, not just the openssl CLI).
if [ "${DRY_RUN}" -eq 0 ] && [ ! -f /usr/include/openssl/ssl.h ]; then
    die "libssl-dev headers not found (/usr/include/openssl/ssl.h). Install libssl-dev."
fi
log "Tool checks passed."

# --- 2. Ubuntu codename detection (informational; documents the host) ---
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    log "Host OS: ${PRETTY_NAME:-unknown} (codename ${VERSION_CODENAME:-unknown})"
else
    warn "/etc/os-release not found; cannot confirm Ubuntu host."
fi

# --- 3. Download tarball over HTTPS only ---
log "Kernel branch: ${KVERSION_MAJOR}.x LTS (example point release ${KVERSION_EXAMPLE}; re-check kernel.org)."
run mkdir -p "${WORK_DIR}"
if [ ! -f "${WORK_DIR}/${TARBALL}" ]; then
    log "Downloading ${TARBALL_URL} ..."
    # HTTPS only. No curl|sh, no HTTP fallback.
    run curl --proto '=https' --tlsv1.2 -fSL -o "${WORK_DIR}/${TARBALL}" "${TARBALL_URL}"
else
    log "Tarball already present: ${WORK_DIR}/${TARBALL}"
fi

# --- Signature verification guidance ---
cat <<EOF
[build-kernel] Signature verification (do this before extracting):
  The tarball's detached OpenPGP signature is at:
    ${SIGN_URL}
  Download it over HTTPS and verify with a trusted kernel.org key, e.g.:
    curl --proto '=https' --tlsv1.2 -fSL -o ${TARBALL}.sign ${SIGN_URL}
    gpg --verify ${TARBALL}.sign ${TARBALL}
  Kernel.org release keys are published at https://kernel.org/category/signatures.html.
  Import the signer's key from a trusted channel (WKD or the kernel.org
  keyring) and check the fingerprint out-of-band. Do NOT proceed if the
  signature does not verify. This script will not extract an unverified
  tarball for you; extract it yourself after verification:
    tar -xf ${WORK_DIR}/${TARBALL} -C ${WORK_DIR}
EOF

if [ "${DRY_RUN}" -eq 1 ]; then
    printf '[dry-run] would stop here for manual signature verification and extraction.\n'
fi

if [ ! -d "${SRC_DIR}" ]; then
    if [ "${DRY_RUN}" -eq 1 ]; then
        printf '[dry-run] would require extracted source at %s\n' "${SRC_DIR}"
    else
        die "source not extracted at ${SRC_DIR}. Verify the signature (above), extract, then re-run."
    fi
fi

# --- 4. Apply config fragment via merge_config.sh ---
log "Applying ${PROFILE} config fragment..."
MERGE_SCRIPT="${SRC_DIR}/scripts/kconfig/merge_config.sh"
if [ "${DRY_RUN}" -eq 0 ] && [ ! -x "${MERGE_SCRIPT}" ]; then
    die "merge_config.sh not found at ${MERGE_SCRIPT}"
fi
BASE_CONFIG="/boot/config-$(uname -r)"
if [ "${DRY_RUN}" -eq 0 ] && [ ! -f "${BASE_CONFIG}" ]; then
    die "distro base config not found: ${BASE_CONFIG}"
fi
run cp "${BASE_CONFIG}" "${SRC_DIR}/.config"
if [ "${PROFILE}" = "diagnostic" ]; then
    run bash "${MERGE_SCRIPT}" -m "${SRC_DIR}/.config" \
        "${CONFIG_DIR}/hardened.config" "${CONFIG_DIR}/diagnostic.config"
else
    run bash "${MERGE_SCRIPT}" -m "${SRC_DIR}/.config" \
        "${CONFIG_DIR}/hardened.config"
fi
log "Resolving remaining symbols against 6.18 defaults..."
run make -C "${SRC_DIR}" olddefconfig
warn "REVIEW any new prompts olddefconfig resolved; this fragment is a first pass."

# --- 5. Module signing (skip cleanly with warning if no key) ---
SIGN_KEY="${REPO_ROOT}/repo/keys/signing_key.pem"
SIGN_CERT="${REPO_ROOT}/repo/keys/signing_key.x509"
if [ -f "${SIGN_KEY}" ] && [ -f "${SIGN_CERT}" ]; then
    log "Project signing key found; modules will be signed."
    run cp "${SIGN_KEY}" "${SRC_DIR}/certs/signing_key.pem"
    run cp "${SIGN_CERT}" "${SRC_DIR}/certs/signing_key.x509"
else
    warn "no project signing key at repo/keys/. Modules will build UNSIGNED and will be REJECTED at load time under CONFIG_MODULE_SIG_FORCE. Generate a key before installing, or this kernel will boot without loadable modules."
fi

# --- 6. Build .deb packages ---
NPROC="$(nproc)"
log "Building kernel .debs with make deb-pkg (-j${NPROC})..."
run make -C "${SRC_DIR}" -j"${NPROC}" deb-pkg

# --- 7. Refuse to remove kernels ---
log "Build finished. This script never removes kernels."
log "The Ubuntu distro kernel and all previously installed custom kernels remain installed as rescue/fallback entries."

# --- Next steps ---
cat <<EOF
[build-kernel] Next steps (manual, in order):
  1. Install the .debs from ${WORK_DIR} (linux-image, linux-headers), e.g.:
       sudo dpkg -i ${WORK_DIR}/linux-image-*.deb ${WORK_DIR}/linux-headers-*.deb
  2. If Secure Boot is enabled later: sign the kernel image and enroll the
     project key in MOK (shim+MOK flow); verify with: mokutil --sb-state
  3. Update the bootloader and CONFIRM the new entry is NOT the only entry:
     the Ubuntu distro kernel entry must remain bootable as rescue.
  4. Reboot into the new kernel; run the test plan in
     repo/docs/KERNEL_VERSION_POLICY.md (boot hardened, boot diagnostic,
     rescue fallback check, s2idle suspend/resume smoke, dmesg review).
  5. Record the build in repo/docs/PATCH_TRACKING.md (create it): release
     tag, check date, CVEs covered, test result.
  6. If anything fails: boot the previous working kernel, keep the distro
     rescue entry, and record the failure. Do not delete the broken kernel
     until its replacement is verified working.
EOF

if [ "${DRY_RUN}" -eq 1 ]; then
    log "Dry run complete: no changes were made."
fi
