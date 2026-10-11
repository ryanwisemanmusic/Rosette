#!/usr/bin/env python3
"""Audit Rosette's source-vendored third-party library contracts.

The catalogue is intentionally split into two layers:

* ``pkg/vendor/src/manifest.toml`` owns versions, upstream commits, and the
  content hashes of the canonical source snapshots.
* each ``pkg/vendor/<arch>/<platform>/target.toml`` owns only the ABI and
  provider choice for that route.

This tool checks both layers, compares Xenia's submodules with the pinned
commits, probes the local macOS providers when they exist, and compiles the
Vulkan header contract for the three Rosette host architectures.  A host
library that is merely newer than the reproducible source baseline is a
warning: Vulkan's loader/ICD is negotiated at runtime and Xenia only requires
Vulkan 1.0.  ``--strict`` turns source, matrix, and Xenia drift into failures;
it does not pretend that an unavailable Windows or PPC host binary is a local
failure.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

try:
    import tomllib
except ImportError:  # Python < 3.11
    try:
        import tomli as tomllib  # type: ignore[no-redef]
    except ImportError:
        tomllib = None  # type: ignore[assignment]

if tomllib is None:
    # Minimal TOML-subset reader for the vendor catalogue.  ``tomllib`` only
    # ships with Python 3.11+, and ``tomli`` may not be installed on older
    # machines, but the audit is part of the build gate so it must run
    # everywhere.  The catalogue files use a small, regular subset: flat
    # ``key = value`` pairs, ``[table]`` headers, ``[[array-of-tables]]``
    # headers, strings, integers, booleans, and single-line arrays.
    class _TomlDecodeError(ValueError):
        pass

    tomllib = type("tomllib", (), {"load": None, "TOMLDecodeError": _TomlDecodeError})  # type: ignore[assignment]

    def _toml_parse(text: str) -> dict[str, Any]:
        root: dict[str, Any] = {}
        table = root
        array_table: list[dict[str, Any]] | None = None
        for raw_line in text.splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("[[") and line.endswith("]]"):
                name = line[2:-2].strip()
                array_table = root.setdefault(name, [])
                table = {}
                array_table.append(table)
                continue
            if line.startswith("[") and line.endswith("]"):
                name = line[1:-1].strip()
                array_table = None
                table = root.setdefault(name, {})
                continue
            if "=" not in line:
                raise _TomlDecodeError(f"cannot parse line: {raw_line!r}")
            key, _, value_text = line.partition("=")
            key = key.strip()
            value_text = value_text.strip()
            table[key] = _toml_parse_value(value_text, raw_line)
        return root

    def _toml_parse_value(text: str, raw_line: str) -> Any:
        if text.startswith("[") and text.endswith("]"):
            inner = text[1:-1].strip()
            if not inner:
                return []
            return [_toml_parse_value(part.strip(), raw_line) for part in inner.split(",")]
        if (text.startswith('"') and text.endswith('"')) or (text.startswith("'") and text.endswith("'")):
            return text[1:-1]
        if text in ("true", "false"):
            return text == "true"
        if re.fullmatch(r"[+-]?\d+", text):
            return int(text)
        raise _TomlDecodeError(f"cannot parse value {text!r} (line: {raw_line!r})")

    def _toml_load(stream: Any) -> dict[str, Any]:
        return _toml_parse(stream.read().decode("utf-8"))

    tomllib.load = _toml_load  # type: ignore[attr-defined]


ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "pkg" / "vendor"
MANIFEST_PATH = VENDOR / "src" / "manifest.toml"


class Audit:
    def __init__(self, strict: bool) -> None:
        self.strict = strict
        self.results: list[dict[str, Any]] = []

    def add(self, key: str, status: str, message: str, **details: Any) -> None:
        self.results.append(
            {
                "key": key,
                "status": status,
                "message": message,
                "details": details,
            }
        )

    def drift(self, key: str, message: str, **details: Any) -> None:
        self.add(key, "FAIL" if self.strict else "WARN", message, **details)

    @property
    def failures(self) -> list[dict[str, Any]]:
        return [result for result in self.results if result["status"] == "FAIL"]

    @property
    def warnings(self) -> list[dict[str, Any]]:
        return [result for result in self.results if result["status"] == "WARN"]


def read_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as stream:
        return tomllib.load(stream)  # type: ignore[attr-defined]


def tree_hash(root: Path) -> tuple[str, int]:
    """Hash paths and contents, independent of mtime/uid/archive metadata."""

    entries: list[Path] = []
    for candidate in root.rglob("*"):
        if ".git" in candidate.relative_to(root).parts:
            continue
        if candidate.is_file() or candidate.is_symlink():
            entries.append(candidate)

    digest = hashlib.sha256()
    for candidate in sorted(entries, key=lambda path: path.relative_to(root).as_posix()):
        relative = candidate.relative_to(root).as_posix().encode("utf-8")
        digest.update(relative + b"\0")
        if candidate.is_symlink():
            digest.update(b"L\0" + os.readlink(candidate).encode("utf-8"))
        else:
            digest.update(b"F\0")
            with candidate.open("rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(block)
    return digest.hexdigest(), len(entries)


def define(text: str, name: str) -> str | None:
    match = re.search(rf"^\s*#define\s+{re.escape(name)}\s+([^\s/]+)", text, re.MULTILINE)
    return match.group(1) if match else None


def semver(value: str) -> tuple[int, int, int]:
    numbers = [int(part) for part in re.findall(r"\d+", value)[:3]]
    return tuple((numbers + [0, 0, 0])[:3])  # type: ignore[return-value]


def run(command: list[str], cwd: Path | None = None) -> tuple[int, str]:
    try:
        completed = subprocess.run(
            command,
            cwd=cwd,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=45,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return 127, str(error)
    return completed.returncode, completed.stdout.strip()


def parent_gitlink_commit(xenia_root: Path, submodule: str) -> tuple[int, str]:
    """Read a submodule commit from Xenia's parent Git tree.

    A nested checkout may sit on a slow or removable volume whose object pack
    cannot answer even ``rev-parse HEAD`` within the audit timeout.  The parent
    Gitlink is still an exact, content-addressed record of the commit Xenia's
    checked-in source tree requires, and avoids opening the nested packfile.
    """
    return run(["git", "-C", str(xenia_root), "rev-parse", f"HEAD:{submodule}"])


def unique_paths(paths: list[Path]) -> list[Path]:
    result: list[Path] = []
    seen: set[Path] = set()
    for path in paths:
        resolved = path.expanduser()
        if resolved in seen:
            continue
        seen.add(resolved)
        result.append(resolved)
    return result


def source_include(source: Path, relative: str) -> Path:
    return source / relative


def check_catalogue(audit: Audit) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    if not MANIFEST_PATH.is_file():
        audit.add("catalogue", "FAIL", f"missing catalogue: {MANIFEST_PATH}")
        return {}, {}

    try:
        manifest = read_toml(MANIFEST_PATH)
    except (OSError, tomllib.TOMLDecodeError) as error:
        audit.add("catalogue", "FAIL", f"cannot parse catalogue: {error}")
        return {}, {}

    if manifest.get("schema_version") != 1:
        audit.add("catalogue-schema", "FAIL", "unsupported vendor catalogue schema", value=manifest.get("schema_version"))
    else:
        audit.add("catalogue-schema", "PASS", "vendor catalogue schema is supported")

    libraries = manifest.get("libraries", [])
    library_map = {library.get("id"): library for library in libraries if library.get("id")}
    if len(library_map) != len(libraries):
        audit.add("catalogue-library-ids", "FAIL", "library ids are missing or duplicated")
    else:
        audit.add("catalogue-library-ids", "PASS", f"catalogue contains {len(library_map)} unique libraries")

    for library_id, library in library_map.items():
        source = VENDOR / library["source_dir"]
        if not source.is_dir():
            audit.add(f"source:{library_id}", "FAIL", "canonical source snapshot is missing", path=str(source))
            continue
        actual_hash, file_count = tree_hash(source)
        expected_hash = library.get("source_tree_sha256")
        if actual_hash != expected_hash:
            audit.drift(
                f"source-hash:{library_id}",
                "canonical source snapshot hash differs from the catalogue",
                expected=expected_hash,
                actual=actual_hash,
                files=file_count,
            )
        else:
            audit.add(f"source-hash:{library_id}", "PASS", "canonical source snapshot hash matches", files=file_count)

        license_path = source / library.get("license_file", "")
        if license_path.is_file():
            audit.add(f"source-license:{library_id}", "PASS", "declared license file is present")
        else:
            audit.add(f"source-license:{library_id}", "WARN", "declared license file was not found", path=str(license_path))

    matrix = manifest.get("matrix", {})
    expected_architectures = set(matrix.get("architectures", []))
    expected_platforms = set(matrix.get("platforms", []))
    target_files = sorted(VENDOR.glob("x86/*/target.toml"))
    target_files += sorted(VENDOR.glob("ARM64/*/target.toml"))
    target_files += sorted(VENDOR.glob("PPC/*/target.toml"))
    targets: dict[str, dict[str, Any]] = {}
    for target_path in target_files:
        try:
            target = read_toml(target_path)
        except (OSError, tomllib.TOMLDecodeError) as error:
            audit.add(f"target:{target_path}", "FAIL", f"cannot parse target record: {error}")
            continue
        target_id = target.get("target_id")
        if not target_id or target_id in targets:
            audit.add(f"target:{target_path}", "FAIL", "target id is missing or duplicated")
            continue
        targets[target_id] = target
        architecture = target.get("architecture")
        target_platform = target.get("platform")
        source_root = (target_path.parent / target.get("source_root", "")).resolve()
        target_libraries = set(target.get("libraries", []))
        missing = target_libraries - set(library_map)
        if architecture not in expected_architectures or target_platform not in expected_platforms:
            audit.add(f"target-shape:{target_id}", "FAIL", "target uses an unknown architecture or platform", architecture=architecture, platform=target_platform)
        elif missing:
            audit.add(f"target-libraries:{target_id}", "FAIL", "target references unknown libraries", missing=sorted(missing))
        elif not source_root.is_dir():
            audit.add(f"target-source:{target_id}", "FAIL", "target source root does not resolve", path=str(source_root))
        elif "version" in target or "commit" in target:
            audit.add(f"target-single-source:{target_id}", "FAIL", "target record duplicates a version/commit; keep it in manifest.toml")
        else:
            audit.add(f"target:{target_id}", "PASS", "target ABI/provider record is complete")

    expected_target_count = int(matrix.get("expected_target_count", 0))
    if len(targets) != expected_target_count:
        audit.add("target-count", "FAIL", "architecture/platform matrix is incomplete", expected=expected_target_count, actual=len(targets))
    else:
        audit.add("target-count", "PASS", f"architecture/platform matrix contains {len(targets)} targets")

    expected_ids = {f"{architecture}-{target_platform}" for architecture in expected_architectures for target_platform in expected_platforms}
    missing_ids = expected_ids - set(targets)
    extra_ids = set(targets) - expected_ids
    if missing_ids or extra_ids:
        audit.add("target-ids", "FAIL", "target matrix ids do not cover the declared cross product", missing=sorted(missing_ids), extra=sorted(extra_ids))
    else:
        audit.add("target-ids", "PASS", "target matrix covers every declared architecture/platform pair")

    library_ids = set(library_map)
    for target_id, target in targets.items():
        if set(target.get("libraries", [])) != library_ids:
            audit.add(f"target-equivalence:{target_id}", "FAIL", "target does not expose the complete common library set")
    if targets and all(set(target.get("libraries", [])) == library_ids for target in targets.values()):
        audit.add("target-library-equivalence", "PASS", "all target records reference the same canonical library set")

    audit.add("catalogue", "PASS", "vendor catalogue and target records loaded")
    return manifest, library_map


def check_xenia(audit: Audit, manifest: dict[str, Any], libraries: dict[str, dict[str, Any]], xenia_root: Path | None) -> None:
    if xenia_root is None:
        audit.add("xenia", "SKIP", "Xenia root was not supplied; source and host checks still ran")
        return
    if not xenia_root.is_dir():
        audit.add("xenia", "FAIL", "supplied Xenia root does not exist", path=str(xenia_root))
        return

    for library_id, library in libraries.items():
        submodule = library.get("xenia_submodule", "")
        if not submodule:
            continue
        path = xenia_root / submodule
        if not path.is_dir():
            audit.add(f"xenia-source:{library_id}", "SKIP", "Xenia submodule is not checked out", path=str(path))
            continue
        parent_code, parent_commit = parent_gitlink_commit(xenia_root, submodule)
        if parent_code == 0 and re.fullmatch(r"[0-9a-fA-F]{40}", parent_commit):
            # The parent Gitlink is the commit Xenia's checked-in source tree
            # requires. Prefer it because reading a nested checkout can force
            # Git to open a multi-hundred-megabyte pack on a removable volume.
            code, actual_commit = 0, parent_commit.lower()
            commit_source = "parent Gitlink"
        else:
            code, actual_commit = run(["git", "-C", str(path), "rev-parse", "HEAD"])
            commit_source = "nested checkout"
            if code != 0:
                audit.add(
                    f"xenia-source:{library_id}",
                    "FAIL",
                    "could not read Xenia submodule commit or parent Gitlink",
                    output=actual_commit,
                    parent_output=parent_commit,
                )
        if code == 0 and actual_commit != library.get("commit"):
            audit.drift(
                f"xenia-source:{library_id}",
                "Xenia submodule commit differs from the vendored baseline",
                expected=library.get("commit"),
                actual=actual_commit,
                source=commit_source,
            )
        elif code == 0:
            audit.add(
                f"xenia-source:{library_id}",
                "PASS",
                "Xenia submodule commit matches vendored baseline",
                source=commit_source,
            )

        if commit_source == "parent Gitlink":
            audit.add(
                f"xenia-dirty:{library_id}",
                "SKIP",
                "nested checkout status is intentionally not scanned; parent Gitlink is the source-tree contract",
            )
            continue

        dirty_code, dirty = run(["git", "-C", str(path), "status", "--porcelain"])
        if dirty_code == 0 and dirty:
            audit.drift(
                f"xenia-dirty:{library_id}",
                "Xenia submodule has local edits; the clean vendored snapshot remains authoritative",
                changed_files=dirty.splitlines(),
            )
        elif dirty_code == 0:
            audit.add(f"xenia-dirty:{library_id}", "PASS", "Xenia submodule working tree is clean")

    xenia_facts = manifest.get("xenia", {})
    header = xenia_root / "third_party" / "Vulkan-Headers" / "include" / "vulkan" / "vulkan_core.h"
    if header.is_file():
        header_version = define(header.read_text(encoding="utf-8", errors="replace"), "VK_HEADER_VERSION")
        expected_header = str(xenia_facts.get("vulkan_header_version", "")).rsplit(".", 1)[-1]
        if header_version == expected_header:
            audit.add("xenia-vulkan-header", "PASS", "Xenia Vulkan header version matches the catalogue", version=header_version)
        else:
            audit.drift("xenia-vulkan-header", "Xenia Vulkan header version differs", expected=expected_header, actual=header_version)
    else:
        audit.add("xenia-vulkan-header", "SKIP", "Xenia Vulkan header was not found")

    instance_header = xenia_root / "src" / "xenia" / "ui" / "vulkan" / "vulkan_instance.h"
    if instance_header.is_file():
        text = instance_header.read_text(encoding="utf-8", errors="replace")
        expected_api = str(xenia_facts.get("vulkan_instance_default_api", "1.0.0"))
        if "VK_MAKE_API_VERSION(0, 1, 0, 0)" in text:
            audit.add("xenia-vulkan-instance-api", "PASS", "Xenia starts Vulkan instance negotiation at Vulkan 1.0", api=expected_api)
        else:
            audit.drift("xenia-vulkan-instance-api", "Xenia Vulkan instance default is not the catalogue contract", expected="VK_MAKE_API_VERSION(0, 1, 0, 0)")
    else:
        audit.add("xenia-vulkan-instance-api", "SKIP", "Xenia Vulkan instance header was not found")

    package_log = xenia_root / xenia_facts.get("package_log", ".rosette/rosette-pkg.log")
    if package_log.is_file():
        text = package_log.read_text(encoding="utf-8", errors="replace")
        summary = re.search(r"=== Summary:\s*(\d+) contracts checked,\s*(\d+) FAILED", text)
        if summary and int(summary.group(2)) == 0:
            audit.add("xenia-package-log", "PASS", "Xenia package contract log reports zero failures", contracts=int(summary.group(1)))
            if "[PASS] vendor-library-contract" in text:
                audit.add("xenia-package-log-vendor", "PASS", "Xenia package log includes the vendored-library contract")
            else:
                audit.drift(
                    "xenia-package-log-vendor",
                    "Xenia package log predates the vendored-library contract; the next Rosette startup must regenerate it",
                    expected="[PASS] vendor-library-contract",
                )
        elif summary:
            audit.drift("xenia-package-log", "Xenia package contract log reports failures", contracts=int(summary.group(1)), failures=int(summary.group(2)))
        else:
            audit.add("xenia-package-log", "WARN", "Xenia package log exists but has no recognizable summary")
    else:
        audit.add("xenia-package-log", "SKIP", "Xenia package log is not present")


def rosette_macos_host_bases() -> list[Path]:
    """Return Rosette-owned providers before compatibility host paths.

    Xenia historically encoded this ordering in x86brew scripts. Keep the
    policy in Rosette's environment variables so the audit and build consume
    the same managed root while still recognizing the old prefixes during the
    migration window.
    """
    bases: list[Path] = []
    managed_root = os.environ.get("ROSETTE_MACOS_HOST_ROOT")
    host_prefix = os.environ.get("ROSETTE_HOST_PREFIX")
    if managed_root:
        root = Path(managed_root)
        bases.extend([root, root / "native", root / "x86_64"])
    if host_prefix:
        bases.append(Path(host_prefix))
    return unique_paths(bases)


def macos_header_candidates(relative: str) -> list[Path]:
    sdk = Path(os.environ["VULKAN_SDK"]) if os.environ.get("VULKAN_SDK") else None
    bases = rosette_macos_host_bases()
    if sdk:
        bases.extend([sdk, sdk / "macOS"])
    bases.extend(
        [
            Path("/usr/local"),
            Path("/opt/homebrew"),
            Path("/Users/ryanwiseman/VulkanSDK/1.3/macOS"),
        ]
    )
    return unique_paths([base / "include" / relative for base in bases])


def check_macos_hosts(audit: Audit, manifest: dict[str, Any], libraries: dict[str, dict[str, Any]]) -> None:
    if platform.system() != "Darwin":
        audit.add("macos-host", "SKIP", "local host is not macOS")
        return

    xenia_facts = manifest.get("xenia", {})
    expected_vulkan = str(xenia_facts.get("vulkan_header_version", ""))
    for header in macos_header_candidates("vulkan/vulkan_core.h"):
        if not header.is_file():
            continue
        version_number = define(header.read_text(encoding="utf-8", errors="replace"), "VK_HEADER_VERSION")
        version = f"1.4.{version_number}" if version_number and version_number.isdigit() else version_number
        if version == expected_vulkan:
            audit.add(f"host-vulkan-header:{header}", "PASS", "macOS Vulkan header matches the vendored baseline", version=version)
        else:
            audit.add(f"host-vulkan-header:{header}", "WARN", "macOS Vulkan header is a provider drift; Xenia should use the vendored include path", expected=expected_vulkan, actual=version)

    for header in macos_header_candidates("SDL2/SDL_version.h"):
        if not header.is_file():
            continue
        text = header.read_text(encoding="utf-8", errors="replace")
        version = ".".join(define(text, name) or "?" for name in ("SDL_MAJOR_VERSION", "SDL_MINOR_VERSION", "SDL_PATCHLEVEL"))
        expected = str(libraries.get("sdl2", {}).get("version", ""))
        if version == expected:
            audit.add(f"host-sdl:{header}", "PASS", "macOS SDL2 header matches the vendored baseline", version=version)
        else:
            audit.add(f"host-sdl:{header}", "WARN", "macOS SDL2 header is a provider drift", expected=expected, actual=version)

    sdk = Path(os.environ["VULKAN_SDK"]) if os.environ.get("VULKAN_SDK") else None
    lib_bases = rosette_macos_host_bases()
    if sdk:
        lib_bases.extend([sdk / "lib", sdk / "macOS" / "lib"])
    lib_bases.extend([Path("/usr/local/lib"), Path("/opt/homebrew/lib")])
    runtime_candidates: list[Path] = []
    for base in lib_bases:
        library_base = base / "lib" if base.name not in {"lib", "Frameworks"} else base
        if library_base.is_dir():
            runtime_candidates.extend(sorted(library_base.glob("libvulkan*.dylib")))
    runtime_candidates = unique_paths(runtime_candidates)
    if not runtime_candidates:
        audit.add("host-vulkan-runtime", "SKIP", "no macOS Vulkan loader dylib was found")
        return

    available_architectures: set[str] = set()
    for runtime in runtime_candidates:
        code, arch_output = run(["lipo", "-archs", str(runtime)])
        architectures = arch_output.split() if code == 0 else []
        available_architectures.update(architectures)
        version_match = re.search(r"libvulkan\.(\d+\.\d+\.\d+)", runtime.name)
        runtime_version = version_match.group(1) if version_match else "unknown"
        audit.add(
            f"host-vulkan-runtime:{runtime}",
            "PASS",
            "macOS Vulkan loader provider discovered",
            version=runtime_version,
            architectures=architectures,
        )

    for required_architecture, label in (("x86_64", "x86_64-macOS"), ("arm64", "aarch64-macOS")):
        if required_architecture in available_architectures:
            audit.add(f"host-runtime-arch:{label}", "PASS", "macOS Vulkan loader has the required architecture", architecture=required_architecture)
        else:
            audit.add(f"host-runtime-arch:{label}", "WARN", "macOS Vulkan loader does not expose the required local architecture", architecture=required_architecture)


def check_architecture_probes(audit: Audit, libraries: dict[str, dict[str, Any]]) -> None:
    vulkan = libraries.get("vulkan-headers")
    if not vulkan:
        return
    include = VENDOR / vulkan["source_dir"] / "include"
    if not include.is_dir():
        return
    source = "#include <vulkan/vulkan_core.h>\n_Static_assert(VK_HEADER_VERSION == 313, \"wrong Vulkan header\");\nint main(void) { return VK_HEADER_VERSION_COMPLETE == 0; }\n"
    targets = ("x86_64-freestanding", "aarch64-freestanding", "powerpc64-freestanding")
    with tempfile.TemporaryDirectory(prefix="rosette-vendor-probe-") as temp:
        probe = Path(temp) / "vulkan_header_probe.c"
        probe.write_text(source, encoding="utf-8")
        for target in targets:
            output = Path(temp) / f"{target}.o"
            code, output_text = run(
                [
                    "zig",
                    "cc",
                    "-target",
                    target,
                    "-c",
                    "-o",
                    str(output),
                    "-I",
                    str(include),
                    str(probe),
                ]
            )
            if code == 0 and output.is_file() and output.stat().st_size > 0:
                audit.add(f"abi-probe:{target}", "PASS", "vendored Vulkan header compiled for architecture", target=target)
            elif code == 127 and "No such file" in output_text:
                audit.add(f"abi-probe:{target}", "SKIP", "zig compiler is unavailable")
            else:
                audit.drift(f"abi-probe:{target}", "vendored Vulkan header failed the architecture probe", target=target, output=output_text[-2000:])


def write_report(audit: Audit, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    report = {
        "schema_version": 1,
        "catalogue": str(MANIFEST_PATH.relative_to(ROOT)),
        "strict": audit.strict,
        "host": {"system": platform.system(), "machine": platform.machine()},
        "summary": {
            "checks": len(audit.results),
            "failures": len(audit.failures),
            "warnings": len(audit.warnings),
        },
        "checks": audit.results,
    }
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--xenia-root", type=Path, help="Xenia checkout to compare against the pinned submodules")
    parser.add_argument("--strict", action="store_true", help="turn source/Xenia/matrix drift warnings into failures")
    parser.add_argument("--json", type=Path, default=ROOT / ".rosette" / "vendor-library-report.json", help="audit report path")
    args = parser.parse_args()

    audit = Audit(strict=args.strict)
    manifest, libraries = check_catalogue(audit)
    if manifest:
        check_xenia(audit, manifest, libraries, args.xenia_root.resolve() if args.xenia_root else None)
        check_macos_hosts(audit, manifest, libraries)
        check_architecture_probes(audit, libraries)
    write_report(audit, args.json if args.json.is_absolute() else ROOT / args.json)

    for result in audit.results:
        print(f"[{result['status']}] {result['key']}: {result['message']}")
    print(f"vendor audit: checks={len(audit.results)} warnings={len(audit.warnings)} failures={len(audit.failures)}")
    return 1 if audit.failures else 0


if __name__ == "__main__":
    sys.exit(main())
