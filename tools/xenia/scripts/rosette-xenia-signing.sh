#!/usr/bin/env bash
# Rosette-owned signing/entitlement preflight for Xenia's script surface.
#
# The old scripts mixed entitlement repair and signing mutations with build
# diagnosis. Rosette exposes the checks and leaves signing as an explicit
# caller action after the binary has been inspected.

set -euo pipefail

rosette_xenia_signing_help() {
    cat <<'EOF'
Rosette Xenia signing adapter

  rosette-xenia-signing.sh --binary path --preflight
  rosette-xenia-signing.sh --binary path --entitlements path --preflight

This command never modifies a binary or entitlement file.
EOF
}

binary=""
entitlements=""
preflight=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --binary)
            [[ $# -ge 2 ]] || { echo "ERROR: --binary requires a path" >&2; exit 2; }
            binary="$2"
            shift 2
            ;;
        --entitlements)
            [[ $# -ge 2 ]] || { echo "ERROR: --entitlements requires a path" >&2; exit 2; }
            entitlements="$2"
            shift 2
            ;;
        --preflight) preflight=1; shift ;;
        --help|-h) rosette_xenia_signing_help; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; rosette_xenia_signing_help >&2; exit 2 ;;
    esac
done
[[ "${preflight}" == 1 ]] || { rosette_xenia_signing_help; exit 0; }
[[ -f "${binary}" ]] || { echo "ERROR: signing target does not exist: ${binary}" >&2; exit 1; }
command -v codesign >/dev/null 2>&1 || { echo "ERROR: codesign is unavailable" >&2; exit 1; }
printf 'binary: %s\n' "${binary}"
file "${binary}"
if [[ -n "${entitlements}" ]]; then
    [[ -f "${entitlements}" ]] || { echo "ERROR: entitlement file does not exist: ${entitlements}" >&2; exit 1; }
    printf 'entitlements: %s\n' "${entitlements}"
fi
printf 'mutation: none\n'

