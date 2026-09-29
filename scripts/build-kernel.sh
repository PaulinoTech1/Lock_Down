#!/usr/bin/env bash
#
# build-kernel.sh -- safe custom-kernel build workflow for the
# thinkpad-hardened-workstation project.
#
# What it does:
#   1. Checks for required build tools.
#   2. Downloads the documented 6.18.x tarball over HTTPS from kernel.org
#      (with .sign signature verification guidance; never curl|sh).
#   3. Applies config/hardened.config (or diagnostic.config) on top of the
#      selected base config and lets Kconfig resolve dependencies.
#   4. Refuses a modular configuration; this monolithic profile has no
#      loadable modules or module-signing key in the build tree.
#   5. Builds binary .deb packages via make bindeb-pkg. The extracted kernel
#      source tree is not a Git checkout, so deb-pkg's source-package check
#      is not applicable to this reproducible build path.
#   6. NEVER removes existing kernels. The distro rescue kernel and old
#      working custom kernels stay installed.
#
# Usage:
#   ./scripts/build-kernel.sh [--profile hardened|diagnostic]
#       [--base-config FILE] [--dry-run]
#
# Next steps after a successful build are printed at the end.
#
# This helper still requires human source-signature verification and a fresh
# extracted tree for an audited release; see ISSUES.md. Never infer provenance
# merely because this script found an existing source directory.

set -euo pipefail

# --- Defaults (overridable via flags) ---
PROFILE="hardened"
DRY_RUN=0
BASE_CONFIG=""

# Kernel branch under test. Keep this aligned with the checked-out source and
# re-verify the point release against kernel.org before a production build.
# See docs/KERNEL_VERSION_POLICY.md for the re-verify requirement.
KVERSION_MAJOR="6.18"
KVERSION_EXAMPLE="6.18.53"
KERNEL_BASE_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/config"
WORK_DIR="${REPO_ROOT}/build"

log()  { printf '[build-kernel] %s\n' "$*"; }
warn() { printf '[build-kernel] WARNING: %s\n' "$*" >&2; }
die()  { printf '[build-kernel] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: build-kernel.sh [--profile hardened|diagnostic] [--base-config FILE] [--dry-run]

  --profile hardened|diagnostic   Which config fragment to apply (default: hardened).
  --base-config FILE              Full base config (default: running distro kernel).
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
        --base-config)
            BASE_CONFIG="${2:?--base-config requires a file}"
            shift 2
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
BASE_CONFIG="${BASE_CONFIG:-/boot/config-$(uname -r)}"

TARBALL="linux-${KVERSION_EXAMPLE}.tar.xz"
TARBALL_URL="${KERNEL_BASE_URL}/${TARBALL}"
# kernel.org signs the uncompressed .tar, not the .tar.xz container.
SIGN_URL="${KERNEL_BASE_URL}/linux-${KVERSION_EXAMPLE}.tar.sign"
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
REQUIRED_CMDS="make gcc flex bison openssl gawk git xz gpg"
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
if [ "${DRY_RUN}" -eq 0 ]; then
    for pkg in debhelper libdw-dev libelf-dev; do
        if ! dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q 'install ok installed'; then
            die "missing Debian package build dependency: ${pkg}. Install it before building .debs."
        fi
    done
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
if [ -d "${SRC_DIR}" ]; then
    log "Using already extracted source: ${SRC_DIR}"
elif [ ! -f "${WORK_DIR}/${TARBALL}" ]; then
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
    curl --proto '=https' --tlsv1.2 -fSL -o linux-${KVERSION_EXAMPLE}.tar.sign ${SIGN_URL}
    set -o pipefail
    xz -cd ${WORK_DIR}/${TARBALL} | gpg --verify linux-${KVERSION_EXAMPLE}.tar.sign -
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

# --- 4. Apply config fragment ---
log "Applying ${PROFILE} config fragment..."
if [ "${DRY_RUN}" -eq 0 ] && [ ! -f "${BASE_CONFIG}" ]; then
    die "base config not found: ${BASE_CONFIG}"
fi
run cp "${BASE_CONFIG}" "${SRC_DIR}/.config"
# Kconfig resolves the complete dependency graph after merging. Required
# symbols are checked below so a silently dropped assignment blocks the build.
MERGE_SCRIPT="${SRC_DIR}/scripts/kconfig/merge_config.sh"
if [ "${PROFILE}" = "diagnostic" ]; then
    run env KCONFIG_CONFIG="${SRC_DIR}/.config" bash "${MERGE_SCRIPT}" -m \
        "${SRC_DIR}/.config" "${CONFIG_DIR}/hardened.config" "${CONFIG_DIR}/diagnostic.config"
else
    run env KCONFIG_CONFIG="${SRC_DIR}/.config" bash "${MERGE_SCRIPT}" -m \
        "${SRC_DIR}/.config" "${CONFIG_DIR}/hardened.config"
fi
log "Resolving remaining symbols against 6.18 defaults..."
run make -C "${SRC_DIR}" olddefconfig
run make -C "${SRC_DIR}" listnewconfig
if [ "${DRY_RUN}" -eq 0 ]; then
    "${REPO_ROOT}/scripts/preflight-check.sh" "${SRC_DIR}/.config" \
        "${CONFIG_DIR}/required-symbols.txt" || die "required config check failed"
    if [ "${PROFILE}" = "hardened" ]; then
        bash "${REPO_ROOT}/scripts/preflight-security.sh" "${SRC_DIR}/.config" || \
            die "resolved security policy check failed"
    else
        warn "Diagnostic profile: production debug-exclusion gate does not apply; this is not a production candidate."
    fi
fi
warn "Review merge overrides and Kconfig output before using the image."

# --- 5. Module policy ---
if [ "${DRY_RUN}" -eq 1 ]; then
    log "Dry run: monolithic module policy will be checked after Kconfig resolution."
elif grep -q '^CONFIG_MODULES=y$' "${SRC_DIR}/.config"; then
    die "modular configuration is unsupported by this signing workflow"
else
    log "CONFIG_MODULES is disabled; monolithic build has no loadable modules to sign."
fi

# --- 6. Build binary .deb packages ---
NPROC="$(nproc)"
log "Building kernel binary .debs with make bindeb-pkg (-j${NPROC})..."
run make -C "${SRC_DIR}" -j"${NPROC}" bindeb-pkg

# --- 7. Refuse to remove kernels ---
log "Build finished. This script never removes kernels."
log "The Ubuntu distro kernel and all previously installed custom kernels remain installed as rescue/fallback entries."

# --- Next steps ---
cat <<EOF
[build-kernel] Next steps (manual, in order):
  1. Identify one exact release's image package by metadata and SHA-256.
     Do not use a broad linux-image-*.deb glob: older failed builds coexist.
  2. Secure Boot is enabled on the target: sign that final package's kernel
     image with the enrolled key and verify it before installing the package.
  3. Install only the exact signed package. The post-install hooks generate
     dracut initramfs and GRUB entries; inspect both before any reboot and
     CONFIRM the Ubuntu distro kernel remains the default rescue entry.
  4. After the owner confirms the pre-boot evidence, select the candidate
     manually from GRUB and use docs/AUDIT3_BOOT_CHECKLIST.md (including
     LUKS, graphics, network, audio, s2idle, journal, and fallback checks).
  5. Record the build in repo/docs/PATCH_TRACKING.md (create it): release
     tag, check date, CVEs covered, test result.
  6. If anything fails: boot the previous working kernel, keep the distro
     rescue entry, and record the failure. Do not delete the broken kernel
     until its replacement is verified working.
EOF

if [ "${DRY_RUN}" -eq 1 ]; then
    log "Dry run complete: no changes were made."
fi
