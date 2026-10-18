#!/usr/bin/env bash
# Populate local SDK reference headers and ensure the pinned AvxToNeon source
# is present in Rosette's tracked vendor tree. Libraries must not live in
# `.rosette`; only machine-local or non-redistributable references do.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REF="${ROOT}/.rosette"
VENDOR="${ROOT}/pkg/vendor/sources/rosette-reference"

mkdir -p "${REF}/include/win32" "${VENDOR}"

clone_if_missing() {
    local url="$1"
    local dest="$2"
    if [[ -d "${dest}/.git" ]] || [[ -f "${dest}/README.md" ]] || [[ -f "${dest}/LICENSE" ]]; then
        echo "  ok  ${dest}"
        return 0
    fi
    echo "  clone ${url} -> ${dest}"
    git clone --depth 1 "${url}" "${dest}"
}

echo "==> Windows 10 SDK headers (tpn/winsdk-10)"
if [[ ! -d "${REF}/winsdk-10/10.0.10240.0" ]]; then
    clone_if_missing "https://github.com/tpn/winsdk-10.git" "${REF}/winsdk-10"
else
    echo "  ok  ${REF}/winsdk-10"
fi

echo "==> Third-party: AvxToNeon (was a git submodule)"
AVX_DEST="${VENDOR}/AvxToNeon"
AVX_ARCHIVE_SHA256="385f0d072d466a013fef6a6ab2cbc62404d5a8c25a04e26aaa57904dff4c8e16"
AVX_COMMIT="a077d3fd59e915b3e1f742560b3850edd5057ec7"
if [[ -f "${AVX_DEST}/LICENSE" && -f "${AVX_DEST}/avx2neon.h" ]]; then
    echo "  ok  ${AVX_DEST} (pinned ${AVX_COMMIT})"
else
    tmp="$(mktemp -d "${VENDOR}/.avx-to-neon.XXXXXX")"
    trap 'rm -rf "${tmp}"' EXIT
    archive="${tmp}/avx-to-neon.tar.gz"
    curl -fL --retry 3 "https://github.com/kunpengcompute/AvxToNeon/archive/${AVX_COMMIT}.tar.gz" -o "${archive}"
    actual_sha="$(shasum -a 256 "${archive}" | awk '{print $1}')"
    [[ "${actual_sha}" == "${AVX_ARCHIVE_SHA256}" ]] || {
        echo "AvxToNeon archive digest mismatch: ${actual_sha}" >&2
        exit 1
    }
    mkdir "${tmp}/unpack"
    tar -xzf "${archive}" -C "${tmp}/unpack"
    staged="${tmp}/unpack/AvxToNeon-${AVX_COMMIT}"
    [[ -f "${staged}/LICENSE" && -f "${staged}/avx2neon.h" ]] || {
        echo "AvxToNeon source archive is incomplete" >&2
        exit 1
    }
    mv "${staged}" "${AVX_DEST}"
fi

echo ""
echo "Local reference headers ready under ${REF}; vendored source under ${VENDOR}."
echo "Do not copy SDK/reference material into the tracked vendor tree."
