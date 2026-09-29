#!/usr/bin/env bash
# JSON provenance, not a reproducibility certificate. Caller writes atomically.
set -euo pipefail
[[ $# -ge 9 ]] || { echo 'usage: write-build-manifest.sh VERSION RELEASE ARCHIVE SIGNER REQUESTED RESOLVED FIRMWARE COMMIT PACKAGE...' >&2; exit 2; }
version="$1" release="$2" archive="$3" signer="$4" requested="$5" resolved="$6" firmware="$7" commit="$8"
shift 8
hash() { sha256sum -- "$1" | cut -d' ' -f1; }
quote() {
    local s="$1"
    # JSON strings: reject controls rather than emit invalid JSON.
    [[ ! "$s" =~ [[:cntrl:]] ]] || { echo 'FAIL control character in manifest value' >&2; return 1; }
    s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}
field() { printf '  "%s": ' "$1"; quote "$2"; printf ',\n'; }
for f in "$archive" "$requested" "$resolved" "$firmware" "$@"; do [[ -f "$f" && ! -L "$f" ]] || { echo 'FAIL missing/nonregular manifest input' >&2; exit 1; }; done
compiler="${CC:-gcc}"
compiler_version="$("$compiler" --version | sed -n '1p')"
binutils_version="$(ld --version | sed -n '1p')"
timestamp="${BUILD_TIMESTAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
printf '{\n'
field schema lockdown.build-provenance.v1
field kernel_version "$version"
field kernel_release "$release"
field localversion "${release#"$version"}"
field source_archive "$(basename -- "$archive")"
field source_archive_sha256 "$(hash "$archive")"
field source_signer_fingerprint "$signer"
field source_tree_identity "pristine-archive-sha256:$(hash "$archive")"
field requested_config_sha256 "$(hash "$requested")"
field resolved_config_sha256 "$(hash "$resolved")"
field firmware_dropin_sha256 "$(hash "$firmware")"
field git_repository_commit "$commit"
field compiler "$compiler"
field compiler_version "$compiler_version"
field binutils_version "$binutils_version"
field build_timestamp "$timestamp"
printf '  "patch_series_sha256": null,\n  "patch_series_status": "NOT_APPLICABLE",\n'
printf '  "signed_inner_image_sha256": null,\n  "signing_status": "UNKNOWN_NOT_SIGNED_BY_BUILD",\n'
printf '  "packages": ['
separator=''
for package in "$@"; do
    printf '%s\n    {"filename": ' "$separator"
    quote "$(basename -- "$package")"
    printf ', "sha256": '; quote "$(hash "$package")"; printf '}'
    separator=','
done
printf '\n  ]\n}\n'
