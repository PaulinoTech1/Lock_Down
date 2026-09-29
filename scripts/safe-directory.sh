#!/usr/bin/env bash
# Sourced by helpers. Reject symlinks and writable/untrusted ancestors.
safe_directory() {
    local path="$1" part uid mode bits
    [[ "$path" == /* && -d "$path" && ! -L "$path" ]] || return 1
    [[ "$(realpath -s -- "$path")" == "$(realpath -e -- "$path")" ]] || return 1
    part="$(realpath -e -- "$path")"
    while :; do
        uid="$(stat -c %u -- "$part")" || return 1
        mode="$(stat -c %a -- "$part")" || return 1
        [[ "$uid" == "$EUID" || "$uid" == 0 ]] || return 1
        bits=$((8#$mode))
        # Root-owned sticky ancestors such as /tmp are safe for private children.
        if (( bits & 0022 )); then
            [[ "$part" != "$path" && "$uid" == 0 ]] && (( bits & 01000 )) || return 1
        fi
        [[ "$part" != / ]] || break
        part="$(dirname -- "$part")"
    done
}
