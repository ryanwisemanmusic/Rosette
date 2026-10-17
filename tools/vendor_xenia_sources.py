#!/usr/bin/env python3
"""Create a clean, commit-pinned source mirror of Xenia's third-party tree.

The exporter reads the checked-in Xenia tree and submodule gitlinks only. It
does not run Xenia, initialize submodules, or copy dirty/untracked files. The
result is kept separate from Rosette's host-provider catalogue because these
are source snapshots owned by Xenia, not Rosette ABI provider choices.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "pkg" / "vendor"
SOURCE_ROOT = VENDOR / "sources"
LICENSE_TARGET = VENDOR / "licenses" / "xenia-canary.txt"
LOCK_TARGET = VENDOR / "xenia-canary.lock.json"
LICENSE_NAMES = {
    "license",
    "license.txt",
    "license.md",
    "license.rst",
    "copying",
    "copying.txt",
    "copying.md",
    "copying.lib",
    "copying.less",
    "notice",
    "notice.txt",
    "notice.md",
}


def run_git(repo: Path, *args: str) -> str:
    completed = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} failed in {repo}: "
            f"{completed.stderr.strip() or completed.stdout.strip()}"
        )
    return completed.stdout.strip()


def parse_tree_entry(raw: bytes) -> tuple[str, str, str, str]:
    meta, name = raw.split(b"\t", 1)
    mode, kind, object_id = meta.decode("ascii").split()
    return mode, kind, object_id, name.decode("utf-8", "surrogateescape")


def tree_entries(repo: Path, treeish: str, *path: str, recursive: bool = False) -> list[tuple[str, str, str, str]]:
    command = ["ls-tree", "-z"]
    if recursive:
        command.append("-r")
    # Passing `commit third_party` lists the `third_party` tree itself; Git's
    # treeish syntax is required to enumerate its immediate children.
    command.append(f"{treeish}:{'/'.join(path)}" if path else treeish)
    output = subprocess.run(
        ["git", "-C", str(repo), *command],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if output.returncode != 0:
        raise RuntimeError(output.stderr.decode("utf-8", "replace").strip())
    return [parse_tree_entry(entry) for entry in output.stdout.split(b"\0") if entry]


def safe_member_path(name: str, strip_prefix: str | None) -> PurePosixPath | None:
    path = PurePosixPath(name)
    if strip_prefix:
        prefix = PurePosixPath(strip_prefix)
        try:
            path = path.relative_to(prefix)
        except ValueError:
            return None
    if path.is_absolute() or not path.parts or any(part in {"", ".", ".."} for part in path.parts):
        return None
    return path


def extract_archive(repo: Path, commit: str, destination: Path, strip_prefix: str | None = None) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    process = subprocess.Popen(
        ["git", "-C", str(repo), "archive", "--format=tar", commit],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert process.stdout is not None
    try:
        with tarfile.open(fileobj=process.stdout, mode="r|") as archive:
            for member in archive:
                relative = safe_member_path(member.name, strip_prefix)
                if relative is None:
                    continue
                target = destination.joinpath(*relative.parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                if member.isdir():
                    target.mkdir(exist_ok=True)
                    os.chmod(target, member.mode & 0o777)
                elif member.issym():
                    if target.exists() or target.is_symlink():
                        target.unlink()
                    os.symlink(member.linkname, target)
                elif member.isfile():
                    source = archive.extractfile(member)
                    if source is None:
                        raise RuntimeError(f"archive file has no payload: {member.name}")
                    with source, target.open("wb") as output:
                        shutil.copyfileobj(source, output, length=1024 * 1024)
                    os.chmod(target, member.mode & 0o777)
        stderr = process.stderr.read() if process.stderr else b""
        status = process.wait()
        if status != 0:
            raise RuntimeError(stderr.decode("utf-8", "replace").strip())
    except BaseException:
        process.kill()
        process.wait()
        raise


def gitlinks(repo: Path, commit: str) -> list[tuple[str, str]]:
    result = []
    for mode, _kind, object_id, path in tree_entries(repo, commit, recursive=True):
        if mode == "160000":
            result.append((path, object_id))
    return result


def materialize_repo(repo: Path, commit: str, destination: Path) -> list[dict[str, str]]:
    """Extract one exact Git commit and overlay every nested gitlink commit."""
    extract_archive(repo, commit, destination)
    nested: list[dict[str, str]] = []
    for relative, nested_commit in gitlinks(repo, commit):
        nested_repo = repo / relative
        if not nested_repo.is_dir():
            raise RuntimeError(
                f"Xenia dependency has an uninitialized nested submodule: {nested_repo} "
                f"(required commit {nested_commit})"
            )
        materialize_repo(nested_repo, nested_commit, destination / relative)
        nested.append({"path": relative, "commit": nested_commit})
    return nested


def hash_tree(root: Path) -> tuple[str, int]:
    entries = [
        path
        for path in root.rglob("*")
        if path.is_file() or path.is_symlink()
    ]
    digest = hashlib.sha256()
    for path in sorted(entries, key=lambda item: item.relative_to(root).as_posix()):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        digest.update(relative + b"\0")
        if path.is_symlink():
            digest.update(b"L\0" + os.readlink(path).encode("utf-8"))
        else:
            digest.update(b"F\0")
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
    return digest.hexdigest(), len(entries)


def license_paths(root: Path) -> list[str]:
    names = {name.casefold() for name in LICENSE_NAMES}
    return sorted(
        path.relative_to(root).as_posix()
        for path in root.rglob("*")
        if path.is_file() and path.name.casefold() in names
    )


def gitmodules_urls(repo: Path, commit: str) -> dict[str, str]:
    try:
        text = run_git(repo, "show", f"{commit}:.gitmodules")
    except RuntimeError:
        return {}
    sections: list[dict[str, str]] = []
    current: dict[str, str] | None = None
    for line in text.splitlines():
        header = re.match(r"\s*\[submodule\s+\"([^\"]+)\"\]\s*$", line)
        if header:
            current = {"name": header.group(1)}
            sections.append(current)
            continue
        if current is not None and "=" in line:
            key, value = line.split("=", 1)
            current[key.strip()] = value.strip()
    return {item.get("path", ""): item.get("url", "") for item in sections if item.get("path")}


def source_version(repo: Path, commit: str) -> str:
    try:
        value = run_git(repo, "describe", "--tags", "--always", commit)
        return value or commit[:12]
    except RuntimeError:
        return commit[:12]


def slug(value: str) -> str:
    result = re.sub(r"[^a-zA-Z0-9]+", "-", value).strip("-").lower()
    if not result:
        raise ValueError(f"cannot make a package id from {value!r}")
    return result


def version_folder(value: str) -> str:
    """Return a readable package-version directory without provenance labels."""
    value = re.sub(r"^(?:release-|v)", "", value, flags=re.IGNORECASE)
    result = re.sub(r"[^a-zA-Z0-9._+-]+", "-", value).strip("-._")
    return result or "unknown"


def manifest_source_dirs() -> set[str]:
    """Return source paths already owned by Rosette's provider catalogue."""
    manifest = VENDOR / "src" / "manifest.toml"
    if not manifest.is_file():
        return set()
    return {
        match.group(1)
        for line in manifest.read_text(encoding="utf-8").splitlines()
        if (match := re.match(r'\s*source_dir\s*=\s*"([^"]+)"', line))
    }


def choose_source_dir(
    dependency_id: str,
    version: str,
    commit: str,
    tree_hash: str,
    old_source_dirs: set[str],
) -> PurePosixPath:
    """Use a package-root path unless that root belongs to another source tree.

    Existing versioned packages are reused when their bytes match. Otherwise,
    a second version is placed below the package's normal name, never below a
    repository-specific wrapper directory.
    """
    package = PurePosixPath("sources") / dependency_id
    package_path = VENDOR.joinpath(*package.parts)
    if package.as_posix() in old_source_dirs or not package_path.exists():
        return package

    if package_path.is_dir():
        if hash_tree(package_path)[0] == tree_hash:
            return package
        for child in sorted(package_path.iterdir(), key=lambda path: path.name):
            if child.is_dir() and hash_tree(child)[0] == tree_hash:
                return package / child.name

    versioned = package / version_folder(version)
    versioned_path = VENDOR.joinpath(*versioned.parts)
    if not versioned_path.exists():
        return versioned
    if versioned_path.is_dir() and hash_tree(versioned_path)[0] == tree_hash:
        return versioned

    versioned = package / f"{version_folder(version)}-{commit[:12]}"
    versioned_path = VENDOR.joinpath(*versioned.parts)
    if versioned_path.exists():
        if versioned_path.is_dir() and hash_tree(versioned_path)[0] == tree_hash:
            return versioned
        versioned = package / f"{version_folder(version)}-{commit[:12]}-{tree_hash[:12]}"
        versioned_path = VENDOR.joinpath(*versioned.parts)
        if versioned_path.exists():
            raise RuntimeError(f"refusing to overwrite existing source tree: {versioned}")
    return versioned


def remove_owned_path(relative: str) -> None:
    """Remove one path from the old lock and prune only empty source parents."""
    path = PurePosixPath(relative)
    if path.is_absolute() or not path.parts or any(part in {"", ".", ".."} for part in path.parts):
        raise RuntimeError(f"unsafe path in previous vendor lock: {relative!r}")
    absolute = VENDOR.joinpath(*path.parts)
    if absolute.is_dir() and not absolute.is_symlink():
        shutil.rmtree(absolute)
    elif absolute.exists() or absolute.is_symlink():
        absolute.unlink()

    parent = absolute.parent
    while parent != SOURCE_ROOT and parent.is_relative_to(SOURCE_ROOT):
        try:
            parent.rmdir()
        except OSError:
            break
        parent = parent.parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xenia-root", type=Path, required=True, help="initialized Xenia checkout")
    parser.add_argument("--replace", action="store_true", help="replace an existing Xenia source snapshot")
    parser.add_argument("--dry-run", action="store_true", help="print the pinned dependency inventory without exporting")
    args = parser.parse_args()

    xenia_root = args.xenia_root.expanduser().resolve()
    if not (xenia_root / "third_party" / "CMakeLists.txt").is_file():
        parser.error(f"not a complete Xenia source checkout: {xenia_root}")

    xenia_commit = run_git(xenia_root, "rev-parse", "HEAD")
    xenia_url = run_git(xenia_root, "remote", "get-url", "origin")
    direct_entries = tree_entries(xenia_root, xenia_commit, "third_party")
    dependencies = [entry for entry in direct_entries if entry[0] in {"040000", "160000"}]
    if not dependencies:
        raise RuntimeError("Xenia's third_party tree contains no dependency directories")

    if not args.dry_run and not args.replace and LOCK_TARGET.exists():
        parser.error(f"vendor snapshot already exists; use --replace to update {LOCK_TARGET}")

    module_urls = gitmodules_urls(xenia_root, xenia_commit)
    print(f"Xenia repository: {xenia_url}")
    print(f"Xenia commit:     {xenia_commit}")
    print(f"Dependency dirs:  {len(dependencies)}")
    if args.dry_run:
        for mode, _kind, object_id, name in dependencies:
            commit = object_id if mode == "160000" else xenia_commit
            print(f"{slug(name):32s} {name:32s} {commit}")
        return 0

    VENDOR.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".xenia-vendor-stage-", dir=VENDOR) as temp_name:
        stage_root = Path(temp_name) / "dependencies"
        stage_root.mkdir(parents=True)
        xenia_license = xenia_root / "LICENSE"
        if not xenia_license.is_file():
            raise RuntimeError("Xenia root LICENSE is missing; refusing to publish source without its license")
        staged_license = Path(temp_name) / "xenia-canary.txt"
        shutil.copy2(xenia_license, staged_license)

        previous_lock: dict[str, Any] = {}
        if args.replace and LOCK_TARGET.is_file():
            previous_lock = json.loads(LOCK_TARGET.read_text(encoding="utf-8"))
        old_source_dirs = {
            item["source_dir"]
            for item in previous_lock.get("dependencies", [])
            if isinstance(item, dict) and isinstance(item.get("source_dir"), str)
        }
        shared_source_dirs = manifest_source_dirs()

        lock_dependencies: list[dict[str, Any]] = []
        staged_dependencies: list[tuple[Path, PurePosixPath, str]] = []
        for mode, _kind, object_id, name in dependencies:
            dependency_id = slug(name)
            # For submodules this is the gitlink commit. For an ordinary
            # checked-in directory it is the exact subtree object id.
            source_commit = object_id
            source_repo = xenia_root / "third_party" / name
            source_dir = stage_root / dependency_id
            if mode == "160000":
                nested = materialize_repo(source_repo, source_commit, source_dir)
                upstream = module_urls.get(f"third_party/{name}", "")
                if not upstream:
                    raise RuntimeError(f"Xenia has no committed .gitmodules URL for {name}")
                version = source_version(source_repo, source_commit)
                source_commit_kind = "submodule-gitlink"
            else:
                extract_archive(xenia_root, xenia_commit, source_dir, f"third_party/{name}")
                nested = []
                upstream = f"{xenia_url}/tree/{xenia_commit}/third_party/{name}"
                version = f"xenia-{xenia_commit[:12]}"
                source_commit_kind = "xenia-tree"

            source_hash, file_count = hash_tree(source_dir)
            source_target = choose_source_dir(
                dependency_id,
                version,
                source_commit,
                source_hash,
                old_source_dirs,
            )
            found_licenses = license_paths(source_dir)
            lock_dependencies.append(
                {
                    "id": dependency_id,
                    "name": name,
                    "xenia_path": f"third_party/{name}",
                    "source_dir": source_target.as_posix(),
                    "upstream": upstream,
                    "version": version,
                    "commit": source_commit,
                    "commit_kind": source_commit_kind,
                    "source_tree_sha256": source_hash,
                    "file_count": file_count,
                    "license_files": found_licenses,
                    "license_status": "upstream-files" if found_licenses else "review-required-no-license-file",
                    "nested_gitlinks": nested,
                }
            )
            staged_dependencies.append((source_dir, source_target, source_hash))
            print(f"exported {name}: {file_count:,} files, {source_hash}")

        source_targets = [target.as_posix() for _, target, _ in staged_dependencies]
        if len(source_targets) != len(set(source_targets)):
            raise RuntimeError("multiple Xenia dependencies resolved to the same package source path")

        lock = {
            "schema_version": 1,
            "repository": {
                "name": "Xenia Canary",
                "url": xenia_url,
                "branch": run_git(xenia_root, "branch", "--show-current"),
                "commit": xenia_commit,
                "license_file": LICENSE_TARGET.relative_to(VENDOR).as_posix(),
            },
            "source_root": "sources",
            "dependency_count": len(lock_dependencies),
            "dependencies": lock_dependencies,
        }
        staged_lock = Path(temp_name) / "xenia-canary.lock.json"
        staged_lock.write_text(json.dumps(lock, indent=2, sort_keys=True) + "\n", encoding="utf-8")

        if args.replace:
            for old_source_dir in sorted(old_source_dirs):
                if old_source_dir not in shared_source_dirs:
                    remove_owned_path(old_source_dir)
            old_license = previous_lock.get("repository", {}).get("license_file")
            if old_license and old_license != LICENSE_TARGET.relative_to(VENDOR).as_posix():
                remove_owned_path(old_license)
            old_root = previous_lock.get("source_root")
            if isinstance(old_root, str) and old_root != "sources":
                legacy_root = VENDOR / old_root
                try:
                    legacy_root.rmdir()
                except OSError:
                    pass

        for staged_source, source_target, source_hash in staged_dependencies:
            destination = VENDOR.joinpath(*source_target.parts)
            if destination.exists():
                if destination.is_dir() and hash_tree(destination)[0] == source_hash:
                    continue
                raise RuntimeError(f"refusing to overwrite existing source tree: {source_target}")
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(staged_source), str(destination))

        LICENSE_TARGET.parent.mkdir(parents=True, exist_ok=True)
        if LICENSE_TARGET.exists():
            if LICENSE_TARGET.read_bytes() != staged_license.read_bytes():
                old_license = previous_lock.get("repository", {}).get("license_file")
                if old_license != LICENSE_TARGET.relative_to(VENDOR).as_posix():
                    raise RuntimeError(f"refusing to overwrite existing license file: {LICENSE_TARGET}")
        shutil.copy2(staged_license, LICENSE_TARGET)
        os.replace(staged_lock, LOCK_TARGET)

    print(f"Xenia dependency packages: {SOURCE_ROOT.relative_to(ROOT)}/*")
    print(f"Xenia repository license: {LICENSE_TARGET.relative_to(ROOT)}")
    print(f"Xenia source lock:         {LOCK_TARGET.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"vendor_xenia_sources: {error}", file=sys.stderr)
        raise SystemExit(1)
