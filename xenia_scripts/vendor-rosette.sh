#!/usr/bin/env bash
# Import a Rosette source release into third_party/rosette for static selection.
# The default resolves GitHub's latest release at run time; --tag is useful for
# compatibility checks, and --checkout supports local development snapshots.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
xenia_root="$(cd "${script_dir}/.." && pwd)"
repo="https://github.com/ryanwisemanmusic/Rosette"
tag=""
checkout=""
destination="${xenia_root}/third_party/rosette"
replace=0
runner_binary=""
build_runner=0

usage() {
    cat <<'EOF'
Usage: macos/vendor-rosette.sh [options]

Options:
  --tag TAG               Import the named GitHub release (for example V0.08).
  --checkout PATH         Import a local Rosette development checkout.
  --dest PATH             Destination (default: third_party/rosette).
  --replace               Replace an existing destination after staging succeeds.
  --runner-binary PATH    Copy an already-built standalone rosette_exe_runner.
  --build-runner          Build exe-runner-build inside the staged Rosette tree.
  --help                  Show this help.

Without --tag or --checkout, the script imports the latest GitHub release.
This script only imports sources/builds the optional runner. It never starts Xenia.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag) [[ $# -ge 2 ]] || { echo "--tag requires a value" >&2; exit 2; }; tag="$2"; shift 2 ;;
        --checkout) [[ $# -ge 2 ]] || { echo "--checkout requires a path" >&2; exit 2; }; checkout="$2"; shift 2 ;;
        --dest) [[ $# -ge 2 ]] || { echo "--dest requires a path" >&2; exit 2; }; destination="$2"; shift 2 ;;
        --replace) replace=1; shift ;;
        --runner-binary) [[ $# -ge 2 ]] || { echo "--runner-binary requires a path" >&2; exit 2; }; runner_binary="$2"; shift 2 ;;
        --build-runner) build_runner=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -z "$tag" || -z "$checkout" ]] || { echo "Choose --tag or --checkout, not both" >&2; exit 2; }
[[ -z "$checkout" || -d "$checkout" ]] || { echo "checkout does not exist: $checkout" >&2; exit 2; }
destination="$(mkdir -p "$(dirname "$destination")" && cd "$(dirname "$destination")" && pwd)/$(basename "$destination")"
if [[ -e "$destination" && "$replace" != 1 ]]; then
    echo "destination exists; use --replace to update it: $destination" >&2
    exit 2
fi
if [[ -n "$runner_binary" && ! -x "$runner_binary" ]]; then
    echo "runner is missing or not executable: $runner_binary" >&2
    exit 2
fi

stage_parent="$(dirname "$destination")"
work="$(mktemp -d "${stage_parent}/.rosette-import.XXXXXX")"
stage="${work}/rosette"
mkdir "${stage}"
source_kind=github-release
source_tag=""
source_commit=""
archive_sha256=""

cleanup() { rm -rf "$work"; }
trap cleanup EXIT

if [[ -n "$checkout" ]]; then
    source_kind=development-checkout
    checkout="$(cd "$checkout" && pwd)"
    source_commit="$(git -C "$checkout" rev-parse HEAD 2>/dev/null || printf unknown)"
    rsync -a \
        --exclude='/.git/' --exclude='/.rosette/' --exclude='/ISO_FILE/' \
        --exclude='/.zig-cache/' --exclude='/.zig-global-cache/' --exclude='/zig-out/' \
        --exclude='/build/xenia-windows*/' --exclude='/build/rosette-support/' \
        --exclude='/build/.zig-cache*' --exclude='/build/__.SYMDEF' \
        --exclude='*.SYMDEF' --exclude='*.pyc' --exclude='__pycache__/' \
        "${checkout}/" "${stage}/"
elif [[ -n "$tag" ]]; then
    api="https://api.github.com/repos/ryanwisemanmusic/Rosette/releases/tags/${tag}"
    release="${work}/release.json"
    curl -fsSL "$api" -o "$release"
    source_tag="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag_name"])' "$release")"
    archive_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tarball_url"])' "$release")"
    curl -fL --retry 3 "$archive_url" -o "${work}/rosette.tar.gz"
    archive_sha256="$(shasum -a 256 "${work}/rosette.tar.gz" | awk '{print $1}')"
    mkdir "${work}/unpack"
    tar -xzf "${work}/rosette.tar.gz" -C "${work}/unpack"
    shopt -s nullglob
    roots=("${work}/unpack"/*)
    shopt -u nullglob
    [[ "${#roots[@]}" == 1 && -d "${roots[0]}" ]] || { echo "GitHub source archive has an unexpected layout" >&2; exit 1; }
    rsync -a "${roots[0]}/" "${stage}/"
    source_commit="$source_tag"
else
    api="https://api.github.com/repos/ryanwisemanmusic/Rosette/releases/latest"
    release="${work}/release.json"
    curl -fsSL "$api" -o "$release"
    source_tag="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tag_name"])' "$release")"
    archive_url="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["tarball_url"])' "$release")"
    curl -fL --retry 3 "$archive_url" -o "${work}/rosette.tar.gz"
    archive_sha256="$(shasum -a 256 "${work}/rosette.tar.gz" | awk '{print $1}')"
    mkdir "${work}/unpack"
    tar -xzf "${work}/rosette.tar.gz" -C "${work}/unpack"
    shopt -s nullglob
    roots=("${work}/unpack"/*)
    shopt -u nullglob
    [[ "${#roots[@]}" == 1 && -d "${roots[0]}" ]] || { echo "GitHub source archive has an unexpected layout" >&2; exit 1; }
    rsync -a "${roots[0]}/" "${stage}/"
    source_commit="$source_tag"
fi

if [[ "$build_runner" == 1 ]]; then
    (cd "$stage" && make -f build/Makefile exe-runner-build)
fi
if [[ -n "$runner_binary" ]]; then
    mkdir -p "${stage}/zig-out/bin"
    cp -p "$runner_binary" "${stage}/zig-out/bin/rosette_exe_runner"
fi

launcher_present=false
[[ ! -x "${stage}/tools/xenia/scripts/rosette-xenia-run.sh" ]] || launcher_present=true

python3 - "$stage/.rosette-import.json" "$source_kind" "$source_tag" "$source_commit" "$archive_sha256" "$launcher_present" <<'PY'
import json, sys
from pathlib import Path
path, kind, tag, commit, archive_sha, launcher_present = sys.argv[1:]
runner = next((candidate for candidate in (
    "zig-out/bin/rosette_exe_runner",
    "app/bundling/zig-out/bin/rosette_exe_runner",
) if Path(path).parent.joinpath(candidate).is_file()), None)
Path(path).write_text(json.dumps({
    "schema_version": 1,
    "repository": "https://github.com/ryanwisemanmusic/Rosette",
    "source_kind": kind,
    "release_tag": tag or None,
    "source_revision": commit or None,
    "source_archive_sha256": archive_sha or None,
    "runner": runner,
    "launcher": "tools/xenia/scripts/rosette-xenia-run.sh",
    "launcher_present": launcher_present == "true",
    "static_xenia_ready": launcher_present == "true" and runner is not None
}, indent=2, sort_keys=True) + "\n")
PY

backup=""
if [[ -e "$destination" ]]; then
    backup="${work}/old-rosette"
    mv "$destination" "$backup"
fi
if ! mv "$stage" "$destination"; then
    [[ -z "$backup" ]] || mv "$backup" "$destination"
    echo "failed to install staged Rosette import" >&2
    exit 1
fi

printf 'Rosette source imported: %s\n' "$destination"
printf 'source: %s %s\n' "$source_kind" "${source_tag:-$source_commit}"
if [[ -x "$destination/zig-out/bin/rosette_exe_runner" || -x "$destination/app/bundling/zig-out/bin/rosette_exe_runner" ]]; then
    echo "standalone runner: present"
else
    echo "standalone runner: absent (use --runner-binary or --build-runner before selecting static mode)"
fi
if [[ "$launcher_present" != true ]]; then
    echo "warning: this release predates the Xenia launcher; it is source-importable but cannot be selected by the Xenia macOS adapter" >&2
fi
