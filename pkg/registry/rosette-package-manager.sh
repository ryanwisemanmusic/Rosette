#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_INDEX_URL="$(/bin/cat "$SCRIPT_DIR/package-index-url.txt" 2>/dev/null || true)"
INDEX_URL="${ROSETTE_PACKAGE_INDEX_URL:-$DEFAULT_INDEX_URL}"
PACKAGE_ROOT="${ROSETTE_PACKAGE_ROOT:-${HOME}/.rosette/packages}"
MODE="${1:-install}"
shift || true

TMP_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/rosette-packages.XXXXXX")"
declare -a STAGING_PATHS=()
declare -a BACKUP_PATHS=()
declare -a BACKUP_TARGETS=()
cleanup() {
    local index path backup target
    for index in "${!BACKUP_PATHS[@]}"; do
        backup="${BACKUP_PATHS[$index]}"
        target="${BACKUP_TARGETS[$index]}"
        if [[ -e "$backup" ]]; then
            if [[ ! -e "$target" ]]; then /bin/mv "$backup" "$target" || true
            else /bin/rm -rf "$backup"
            fi
        fi
    done
    for path in "${STAGING_PATHS[@]}"; do /bin/rm -rf "$path"; done
    /bin/rm -rf "$TMP_ROOT"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
INDEX_FILE="$TMP_ROOT/package-index.tsv"

fail() {
    printf 'rosette-package-manager: %s\n' "$1" >&2
    exit 1
}

valid_token() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]
}

valid_package_id() {
    [[ "$1" =~ ^[a-z0-9][a-z0-9._-]{0,127}$ ]]
}

fetch_index() {
    [[ -n "$INDEX_URL" ]] || fail "package-index-url.txt is empty"
    [[ "$INDEX_URL" == https://* ]] || fail "package index must use HTTPS"

    local status
    status="$(/usr/bin/curl --proto '=https' --proto-redir '=https' --location --silent --show-error --max-filesize 1048576 --output "$INDEX_FILE" --write-out '%{http_code}' "$INDEX_URL")" ||
        fail "could not reach the package index; check the network and ROSETTE_PACKAGE_INDEX_URL"
    if [[ "$status" == "404" ]]; then
        printf 'No package catalog has been published at %s yet.\n' "$INDEX_URL"
        : > "$INDEX_FILE"
        return 0
    fi
    [[ "$status" == "200" ]] || fail "package index returned HTTP $status"
    [[ "$(/usr/bin/wc -c < "$INDEX_FILE" | /usr/bin/tr -d ' ')" -le 1048576 ]] || fail "package index exceeds 1 MiB"
}

declare -a PACKAGE_IDS=()
declare -a PACKAGE_VERSIONS=()
declare -a PACKAGE_HASHES=()
declare -a PACKAGE_URLS=()
declare -a PACKAGE_DESCRIPTIONS=()

load_index() {
    fetch_index
    local line rest id version digest url description
    while IFS= read -r line || [[ -n "${line:-}" ]]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" == \#* ]] && continue

        [[ "$line" == *$'\t'* ]] || fail "index row has fewer than five fields"
        id="${line%%$'\t'*}"
        rest="${line#*$'\t'}"
        [[ "$rest" == *$'\t'* ]] || fail "index row for '$id' has fewer than five fields"
        version="${rest%%$'\t'*}"
        rest="${rest#*$'\t'}"
        [[ "$rest" == *$'\t'* ]] || fail "index row for '$id' has fewer than five fields"
        digest="${rest%%$'\t'*}"
        rest="${rest#*$'\t'}"
        [[ "$rest" == *$'\t'* ]] || fail "index row for '$id' has fewer than five fields"
        url="${rest%%$'\t'*}"
        description="${rest#*$'\t'}"
        [[ "$description" != *$'\t'* ]] || fail "index row for '$id' has more than five fields"

        valid_package_id "$id" || fail "package IDs must be lower-case letters, digits, dots, underscores, or hyphens: '$id'"
        valid_token "$version" || fail "invalid version '$version' for '$id'"
        [[ "$digest" =~ ^[A-Fa-f0-9]{64}$ ]] || fail "invalid SHA-256 for '$id'"
        [[ "$url" == https://* ]] || fail "asset URL for '$id' must use HTTPS"
        [[ -n "$description" ]] || description="$id"

        local previous
        for previous in "${PACKAGE_IDS[@]:-}"; do
            [[ "$previous" != "$id" ]] || fail "duplicate package ID '$id'"
        done
        PACKAGE_IDS+=("$id")
        PACKAGE_VERSIONS+=("$version")
        PACKAGE_HASHES+=("$(printf '%s' "$digest" | /usr/bin/tr '[:upper:]' '[:lower:]')")
        PACKAGE_URLS+=("$url")
        PACKAGE_DESCRIPTIONS+=("$description")
        (( ${#PACKAGE_IDS[@]} <= 200 )) || fail "package index exceeds the 200 package limit"
    done < "$INDEX_FILE"
}

show_packages() {
    local index
    for index in "${!PACKAGE_IDS[@]}"; do
        printf '%2d) %-28s %s — %s\n' "$((index + 1))" "${PACKAGE_IDS[$index]}" \
            "${PACKAGE_VERSIONS[$index]}" "${PACKAGE_DESCRIPTIONS[$index]}"
    done
}

resolve_selection() {
    local selection="$1"
    SELECTED_INDICES=()
    if [[ "$selection" == "all" ]]; then
        local index
        for index in "${!PACKAGE_IDS[@]}"; do SELECTED_INDICES+=("$index"); done
        return
    fi

    local item index found
    IFS=',' read -r -a items <<< "$selection"
    for item in "${items[@]}"; do
        [[ "$item" =~ ^[0-9]+$ ]] || fail "selection '$item' is not a package number"
        index=$((item - 1))
        (( index >= 0 && index < ${#PACKAGE_IDS[@]} )) || fail "package number '$item' is out of range"
        found=0
        local prior
        for prior in "${SELECTED_INDICES[@]:-}"; do
            [[ "$prior" != "$index" ]] || found=1
        done
        (( found == 0 )) && SELECTED_INDICES+=("$index")
    done
}

install_package() {
    local index="$1"
    local id="${PACKAGE_IDS[$index]}"
    local version="${PACKAGE_VERSIONS[$index]}"
    local expected_hash="${PACKAGE_HASHES[$index]}"
    local url="${PACKAGE_URLS[$index]}"
    local parent="$PACKAGE_ROOT/$id"
    local destination="$parent/$version"
    local archive="$TMP_ROOT/$id.zip"
    local stage="$parent/.install-$$-$index"
    local backup="$parent/.previous-$$-$index"
    local actual_hash entry listing manifest_id manifest_version

    /bin/mkdir -p "$parent"
    [[ ! -e "$stage" ]] || fail "staging path already exists: $stage"
    STAGING_PATHS+=("$stage")
    /bin/mkdir "$stage"
    printf 'Downloading %s %s...\n' "$id" "$version"
    /usr/bin/curl --proto '=https' --proto-redir '=https' --fail --location --silent --show-error --max-filesize 1073741824 --output "$archive" "$url" ||
        fail "download failed for '$id'"
    actual_hash="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print $1}' | /usr/bin/tr '[:upper:]' '[:lower:]')"
    [[ "$actual_hash" == "$expected_hash" ]] || fail "SHA-256 mismatch for '$id'"

    /usr/bin/unzip -tqq "$archive" || fail "package '$id' is not a valid ZIP archive"
    if /usr/bin/unzip -Z -l "$archive" | /usr/bin/awk 'substr($0, 1, 1) ~ /^[lpcbs]$/ { found = 1 } END { exit found ? 0 : 1 }'; then
        fail "special files and symbolic links are not allowed in package '$id'"
    fi
    listing="$TMP_ROOT/$id.entries"
    /usr/bin/unzip -Z -1 "$archive" > "$listing" || fail "could not list package '$id'"
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        case "$entry" in
            /*|../*|*/../*|*/..|*\\*) fail "unsafe archive path in '$id': $entry" ;;
        esac
    done < "$listing"

    /usr/bin/unzip -q "$archive" -d "$stage/unpacked" || fail "could not extract package '$id'"
    [[ -f "$stage/unpacked/rosette-package.tsv" ]] || fail "package '$id' is missing rosette-package.tsv"
    IFS=$'\t' read -r manifest_id manifest_version < "$stage/unpacked/rosette-package.tsv"
    [[ "$manifest_id" == "$id" && "$manifest_version" == "$version" ]] ||
        fail "package manifest identity does not match index row for '$id'"

    if [[ -e "$destination" ]]; then
        BACKUP_PATHS+=("$backup")
        BACKUP_TARGETS+=("$destination")
        /bin/mv "$destination" "$backup" || fail "could not stage previous '$id' version"
    fi
    if ! /bin/mv "$stage/unpacked" "$destination"; then
        if [[ -e "$backup" ]]; then /bin/mv "$backup" "$destination" || true; fi
        fail "could not activate package '$id'"
    fi
    /bin/rm -rf "$stage" "$backup"
    printf 'Installed %s %s at %s\n' "$id" "$version" "$destination"
}

load_index
if (( ${#PACKAGE_IDS[@]} == 0 )); then
    case "$MODE" in
        install|install-all|install-selected) exit 0 ;;
        *) fail "unknown mode '$MODE'" ;;
    esac
fi

case "$MODE" in
    install)
        if (( $# > 0 )); then
            selection="$*"
        else
            printf 'Optional Rosette packages available:\n'
            show_packages
            printf 'Enter package numbers separated by commas, "all", or press Return to skip: '
            IFS= read -r selection || selection=""
        fi
        [[ -n "${selection:-}" ]] || { printf 'No packages selected.\n'; exit 0; }
        resolve_selection "$selection"
        ;;
    install-all)
        (( $# == 0 )) || fail "install-all takes no package IDs"
        SELECTED_INDICES=()
        local_index=0
        while (( local_index < ${#PACKAGE_IDS[@]} )); do SELECTED_INDICES+=("$local_index"); ((local_index += 1)); done
        ;;
    install-selected)
        (( $# > 0 )) || { printf 'No packages selected.\n'; exit 0; }
        SELECTED_INDICES=()
        for selected_spec in "$@"; do
            IFS=: read -r selected_id selected_version selected_hash extra <<< "$selected_spec"
            valid_package_id "$selected_id" || fail "invalid package ID '$selected_id'"
            valid_token "$selected_version" || fail "invalid version '$selected_version' for '$selected_id'"
            [[ "$selected_hash" =~ ^[A-Fa-f0-9]{64}$ && -z "${extra:-}" ]] || fail "invalid catalog checksum for '$selected_id'"
            match=-1
            for index in "${!PACKAGE_IDS[@]}"; do
                if [[ "${PACKAGE_IDS[$index]}" == "$selected_id" ]]; then
                    [[ "${PACKAGE_VERSIONS[$index]}" == "$selected_version" ]] ||
                        fail "catalog changed after selection for '$selected_id'; refresh the list"
                    [[ "${PACKAGE_HASHES[$index]}" == "$(printf '%s' "$selected_hash" | /usr/bin/tr '[:upper:]' '[:lower:]')" ]] ||
                        fail "catalog checksum changed after selection for '$selected_id'; refresh the list"
                    match="$index"
                    break
                fi
            done
            (( match >= 0 )) || fail "selected package '$selected_id' is not in the published index"
            SELECTED_INDICES+=("$match")
        done
        ;;
    *) fail "usage: $0 {install [numbers...]|install-all|install-selected id:version:sha256...}" ;;
esac

for selected_index in "${SELECTED_INDICES[@]}"; do install_package "$selected_index"; done
