#!/usr/bin/env bash
# Verify the static Rosette import and standalone runner, without building or
# launching Xenia. Set ROSETTE_XENIA_WINDOWS_BUNDLE_DIR to also run the
# launcher's --print preflight against an existing bundle.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
xenia_root="$(cd "${script_dir}/.." && pwd)"
rosette_root="${xenia_root}/third_party/rosette"
source "${script_dir}/rosette-root.sh"

resolved="$(ROSETTE_ROOT= ROSETTE_HOME= rosette_resolve_root "$xenia_root" static)"
[[ "$resolved" == "$rosette_root" ]] || {
    echo "Static route resolved to an unexpected root: $resolved" >&2
    exit 1
}
[[ -x "$rosette_root/tools/guest_runtime/scripts/rosette-guest-run.sh" ]] || {
    echo "Static Rosette launcher is missing" >&2
    exit 1
}
runner="${rosette_root}/zig-out/bin/rosette_exe_runner"
if [[ ! -x "$runner" ]]; then
    runner="${rosette_root}/app/bundling/zig-out/bin/rosette_exe_runner"
fi
[[ -x "$runner" ]] || {
    echo "Static Rosette runner is missing; import it with --runner-binary or build it with --build-runner" >&2
    exit 1
}

bash -n "${script_dir}/build-async.sh" "${script_dir}/build-scratch-async.sh" \
    "${script_dir}/rosette-root.sh" "${script_dir}/vendor-rosette.sh"
"${rosette_root}/tools/guest_runtime/scripts/rosette-guest-run.sh" --help >/dev/null

if [[ -n "${ROSETTE_XENIA_WINDOWS_BUNDLE_DIR:-}" ]]; then
    verify_logs="$(mktemp -d "${TMPDIR:-/tmp}/rosette-static-verify.XXXXXX")"
    ROSETTE_ROOT="$rosette_root" \
    ROSETTE_XENIA_RUNNER="$runner" \
    ROSETTE_XENIA_ROSETTE_DIR="$verify_logs" \
    "${rosette_root}/tools/guest_runtime/scripts/rosette-guest-run.sh" \
        --source-root "$xenia_root" \
        --bundle-dir "$ROSETTE_XENIA_WINDOWS_BUNDLE_DIR" \
        --print
    rm -rf "$verify_logs"
    echo "Static import preflight verified. Xenia was not launched."
else
    echo "Static source selection and runner verified. Set ROSETTE_XENIA_WINDOWS_BUNDLE_DIR for an existing-bundle --print preflight. Xenia was not launched."
fi
